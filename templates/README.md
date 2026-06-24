# Input templates

Header + one example row for every input CSV, taken from the synthetic
`timor_demo` dataset. To start a new region, copy these into
`data_indonesia/<year>/<island>/` and fill them in — column semantics and
units are documented in `data_indonesia/README.md`, and the step-by-step
process in `docs/new_region_guide.md`.

Notes:
- Hourly files (`demand`, both `*_variability`, both village demand files)
  need one row per model hour (default 8 weeks x 168 h = 1,344 rows) — the
  single example row here only shows the format.
- `generators_variability.csv` needs one profile column per generator in
  R_ID order; add/remove columns to match your generators file.
- `network.csv` is only required for grid scenarios; add one z<i> column per
  zone.
