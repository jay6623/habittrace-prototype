# AI V2 fixtures

The AI V2 tests construct anonymous synthetic DataFrames in code. Keep files in this directory only when a reproducible, non-identifying fixture is useful for manual pipeline development.

## Generate the synthetic baseline

From `habittrace_ai_v2`:

```powershell
python fixtures/generate_synthetic.py --rows 800
```

Optional arguments:

- `--rows`: number of plan rows
- `--seed`: deterministic random seed
- `--outdir`: output directory; defaults to `fixtures`

Generated files:

- `synthetic_plans.csv`
- `synthetic_outcomes.csv`
- `synthetic_failure_reasons.csv`
- `synthetic_manifest.json`

## Data relationships

- `ai_plan_inputs` and `ai_plan_outcomes` are joined by `plan_input_id`.
- Failure-reason rows are associated with an outcome and enter training truth only when `user_confirmed = true`.
- The manifest records generation metadata and row counts for review.

## Safety rules

- This data is generated, not observed human behavior.
- Do not report synthetic metrics as product performance, user research, or production evaluation.
- Do not place real exports, authentication tokens, Supabase keys, user notes, email addresses, or stable external identifiers in this directory.
- Do not rename legacy V1 CSV columns and treat them as AI V2 truth. V2 labels must be derived from the V2 plan/outcome/reason contract.
- Use the read-only exporter described in `../README.md` for controlled real-data snapshots, and keep those snapshots out of source control.
