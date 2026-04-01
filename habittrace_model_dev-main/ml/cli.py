"""
CLI entrypoints: train, evaluate, predict, update_personal.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import pandas as pd

from .data import (
    CATEGORY_COL,
    ENERGY_COL,
    FOCUS_COL,
    IMPORTANCE_COL,
    PLANNED_DURATION_COL,
    PLANNED_START_COL,
    TOTAL_TASKS_TODAY_COL,
    USER_ID_COL,
    load_and_clean,
    load_for_failure_training,
    load_for_success_training,
)
from .evaluate import run_evaluation
from .features import PlanTimeFeatureBuilder
from .model_failure import (
    build_failure_pipeline,
    load_failure_pipeline,
    predict_failure_proba_and_contributions,
    save_failure_pipeline,
    train_failure_model,
)
from .model_success import (
    build_success_pipeline,
    load_success_pipeline,
    predict_from_pipeline,
    save_success_pipeline,
    train_success_model,
)
from .personalize import (
    get_user_params,
    is_personalization_active,
    load_calib_params,
    online_update_b,
    online_update_a_b,
    predict_personalized,
    save_calib_params,
    set_user_params,
)


def _df_from_predict_input(data: dict) -> pd.DataFrame:
    """Build single-row DataFrame from predict JSON keys (schema column names)."""
    row = {}
    for key in [
        USER_ID_COL,
        CATEGORY_COL,
        PLANNED_START_COL,
        PLANNED_DURATION_COL,
        IMPORTANCE_COL,
        ENERGY_COL,
        FOCUS_COL,
        TOTAL_TASKS_TODAY_COL,
    ]:
        row[key] = [data.get(key)]
    return pd.DataFrame(row)


def cmd_train(args: argparse.Namespace) -> None:
    outdir = Path(args.outdir)
    outdir.mkdir(parents=True, exist_ok=True)

    # Success model
    df_success, y_success, has_uid = load_for_success_training(args.csv)
    if len(df_success) < 2:
        print("Not enough completed/failed rows to train success model.", file=sys.stderr)
        sys.exit(1)
    fb = PlanTimeFeatureBuilder()
    fb.fit(df_success)
    X = fb.transform(df_success)
    model, names = train_success_model(X, y_success.values, fb.get_feature_names())
    pipeline = build_success_pipeline(fb, model)
    save_success_pipeline(pipeline, outdir / "success_model.joblib")
    print(f"Saved success model to {outdir / 'success_model.joblib'}")

    # Failure model (optional)
    df_fail, y_reasons = load_for_failure_training(args.csv)
    valid_reasons = y_reasons.notna() & (y_reasons.astype(str).str.strip().str.len() > 0)
    if len(df_fail) >= 2 and valid_reasons.sum() >= 2:
        df_fail = df_fail.loc[valid_reasons]
        y_reasons = y_reasons.loc[valid_reasons]
        fb_fail = PlanTimeFeatureBuilder()
        fb_fail.fit(df_fail)
        X_fail = fb_fail.transform(df_fail)
        try:
            model_fail, le, fn = train_failure_model(
                X_fail, y_reasons.values, fb_fail.get_feature_names()
            )
            pipe_fail = build_failure_pipeline(fb_fail, model_fail, le)
            save_failure_pipeline(pipe_fail, outdir / "failure_model.joblib")
            print(f"Saved failure model to {outdir / 'failure_model.joblib'}")
        except ValueError as e:
            print(f"Failure model skipped: {e}", file=sys.stderr)
    else:
        print("Skipping failure model (insufficient failed tasks with reasons).", file=sys.stderr)

    # Calib params placeholder
    calib_path = outdir / "calib_params.json"
    if not calib_path.exists():
        save_calib_params({"users": {}}, calib_path)
        print(f"Initialized {calib_path}")


def cmd_evaluate(args: argparse.Namespace) -> None:
    metrics = run_evaluation(args.csv, args.modeldir)
    print(json.dumps(metrics, indent=2))
    print(f"\nMetrics saved to {Path(args.modeldir) / 'metrics.json'}")


def cmd_predict(args: argparse.Namespace) -> None:
    modeldir = Path(args.modeldir)
    data = json.loads(args.input_json)
    df = _df_from_predict_input(data)
    user_id = data.get(USER_ID_COL)

    pipeline = load_success_pipeline(modeldir / "success_model.joblib")
    fb = pipeline["feature_builder"]
    X = fb.transform(df)
    p_global, contribs = predict_from_pipeline(pipeline, X, top_k=args.top_k)
    p_global_val = float(p_global[0])
    combined = contribs[0]["positive"] + contribs[0]["negative"]
    by_feat = {c["feature"]: c for c in combined}
    out = {
        "p_global_success": p_global_val,
        "top_contributions": sorted(by_feat.values(), key=lambda x: -abs(x["contribution"]))[: args.top_k],
    }

    calib_path = modeldir / "calib_params.json"
    if user_id and calib_path.exists():
        calib = load_calib_params(calib_path)
        b, a = get_user_params(calib, str(user_id))
        n = calib.get("users", {}).get(str(user_id), {}).get("n", 0)
        if n > 0 or b != 0.0 or (a is not None and a != 1.0):
            p_pers = predict_personalized(p_global_val, b, a)
            out["p_personal_success"] = p_pers
        else:
            out["p_personal_success"] = None
    else:
        out["p_personal_success"] = None

    if args.failure_probs and (modeldir / "failure_model.joblib").exists():
        fail_pipe = load_failure_pipeline(modeldir / "failure_model.joblib")
        proba, class_names, _ = predict_failure_proba_and_contributions(
            fail_pipe["model"], X, fail_pipe["feature_names"], fail_pipe["label_encoder"], top_k=args.top_k
        )
        out["failure_type_probs"] = dict(zip(class_names, [float(p) for p in proba[0]]))

    print(json.dumps(out, indent=2))


def cmd_update_personal(args: argparse.Namespace) -> None:
    modeldir = Path(args.modeldir)
    calib_path = modeldir / "calib_params.json"
    calib = load_calib_params(calib_path)
    user_id = args.user_id
    p_global = float(args.p_global)
    y = int(args.y)
    if y not in (0, 1):
        raise ValueError("y must be 0 or 1")

    users = calib.setdefault("users", {})
    u = users.get(user_id, {"b": 0.0, "n": 0, "a": None})
    b = u.get("b", 0.0)
    n = u.get("n", 0) + 1
    a = u.get("a")

    if args.use_scale:
        a = a if a is not None else 1.0
        a, b = online_update_a_b(a, b, p_global, y, n)
        calib = set_user_params(calib, user_id, b, n, a)
    else:
        b = online_update_b(b, p_global, y, n)
        calib = set_user_params(calib, user_id, b, n, None)

    save_calib_params(calib, calib_path)
    print(json.dumps({"user_id": user_id, "n": n, "b": b, **({"a": a} if a is not None else {})}))


def main() -> None:
    parser = argparse.ArgumentParser(prog="ml")
    sub = parser.add_subparsers(dest="command", required=True)

    # train
    p_train = sub.add_parser("train")
    p_train.add_argument("--csv", required=True, help="Path to CSV")
    p_train.add_argument("--outdir", default="artifacts", help="Output directory for artifacts")
    p_train.set_defaults(run=cmd_train)

    # evaluate
    p_eval = sub.add_parser("evaluate")
    p_eval.add_argument("--csv", required=True)
    p_eval.add_argument("--modeldir", default="artifacts")
    p_eval.set_defaults(run=cmd_evaluate)

    # predict
    p_pred = sub.add_parser("predict")
    p_pred.add_argument("--modeldir", default="artifacts")
    p_pred.add_argument("--input_json", required=True, help="JSON object with plan-time fields and optional user_id")
    p_pred.add_argument("--top_k", type=int, default=10)
    p_pred.add_argument("--failure_probs", action="store_true", help="Include failure_type_probs in output")
    p_pred.set_defaults(run=cmd_predict)

    # update_personal
    p_up = sub.add_parser("update_personal")
    p_up.add_argument("--modeldir", default="artifacts")
    p_up.add_argument("--user_id", required=True)
    p_up.add_argument("--p_global", required=True)
    p_up.add_argument("--y", required=True, help="Observed outcome 0 or 1")
    p_up.add_argument("--use_scale", action="store_true", help="Update a_user (scale) as well as b_user")
    p_up.set_defaults(run=cmd_update_personal)

    args = parser.parse_args()
    args.run(args)


if __name__ == "__main__":
    main()
