# HabitTrace V1 model design notes

This document supplements `README.md` with implementation details for the legacy V1 ML pipeline. Use `README.md` for installation and exact CLI commands.

## Design boundary

The V1 models use information available when a task is planned. Task names and post-execution values are not prediction features. Actual times, interruptions, stopped-early flags, final status, and failure reason are outcome data used only for labels, filtering, or later calibration.

## Success model

The success target is binary:

```text
completed/success → 1
failed            → 0
skipped/canceled  → excluded
```

`PlanTimeFeatureBuilder` transforms category, planned date/time, duration, importance, energy, focus, and daily task count into a numeric feature matrix. The classifier is L2-regularized logistic regression.

Feature contributions are reported in transformed feature space:

```text
contribution_i = logistic_coefficient_i × transformed_feature_value_i
```

Contribution values explain the linear model score. They are not causal effects and should not be presented as proof that changing one input will produce the reported outcome change.

## Failure-reason model

The failure classifier trains only on failed rows with a usable reason. Input text is normalized into the supported canonical reason set, and rare labels collapse to `other`.

The model is multinomial logistic regression with an encoded label set. `--failure_probs` returns probabilities only when `failure_model.joblib` exists and is compatible with the success model's transformed feature matrix.

## Personalization

The default calibration form is:

```text
p_personal = sigmoid(logit(p_global) + b_user)
```

The optional scale form is:

```text
p_personal = sigmoid(a_user × logit(p_global) + b_user)
```

`update_personal` performs one regularized online update after an observed outcome. The implementation shrinks small-history updates toward `b = 0` and `a = 1`. `MIN_TASKS_FOR_CALIBRATION` is 30, although the CLI can store and return non-identity parameters before that threshold. Product code should communicate whether a result is globally modeled or sufficiently personalized.

Calibration identity must use a stable authenticated user UUID. Names and email prefixes can change and must not be used as ownership keys.

## Evaluation behavior

When planned timestamps are available, evaluation sorts rows chronologically and uses the latest 20% as validation. Without usable planned timestamps, it falls back to a stratified random split with a fixed random state.

Reported success metrics:

- ROC AUC when both classes are present
- Accuracy at a 0.5 threshold
- Log loss
- Brier score
- Five-bin calibration-curve coordinates

Reported failure metrics:

- Macro F1
- Confusion matrix
- Class names

A small or single-class validation set can produce `null` metrics. Treat that as insufficient evidence, not as a successful evaluation.

## Compatibility with the application schema

The primary Supabase tables use V1 statuses `pending`, `success`, and `failed`. The training CSV loader also accepts common completed/failed synonyms and normalizes them.

The mobile UI maps partially done outcomes to a V1 failed execution with `stopped_early = true`; AI V2 stores the richer `partial` status separately. Do not relabel the V1 training CSV as AI V2 truth by changing column names. AI V2 derives labels from its own immutable plan and outcome tables.

## Artifact safety

- Keep artifact and code versions together.
- Load joblib files only from trusted build output.
- Validate predictions after upgrading scikit-learn or NumPy.
- Run evaluation before deploying retrained artifacts.
- Do not commit private raw user exports.

The V1 artifact format does not include the signed SHA-256 manifest used by AI V2. For stronger lineage and integrity controls, use the `habittrace_ai_v2` package design.
