# Roya's 43-participant MATLAB codes

This package contains **12 rewritten code implementations**. The MATLAB code itself was simplified, rather than only adding comments or section headings. All comments and code explanations are in English.

## What was rewritten

| No. | Edited file | Changes to the code itself |
|---|---|---|
| 1 | `run_batch1_all_subjects.m` | Select files with a loop; classify events with explicit conditions; check each E1 response window and each boundary separately. |
| 2 | `all_4_batch_corrected.m` | The same simpler event and file-selection logic, while preserving the saved four-module batch and its dependencies. |
| 3 | `run_convolution_all43_no_batch.m` | Explicit event decisions and onset loops; clearer names for the input and output EEG objects. |
| 4 | `add_tE1_clean_to_all43.m` | Check events one by one; collect valid onsets with a counter; retain the original header backup and append operation. |
| 5 | `run_convolution_all43.m` | Explicit file/event loops; build the channel and Fourier options step by step. |
| 6 | `make_convolution_glm_results_report.m` | Replace `cellfun`, `accumarray`, and anonymous functions with loops and ordinary functions; calculate descriptive Welch statistics one time point at a time. |
| 7 | `make_sensor_space_publication_report.m` | Read group membership one design row at a time; combine result tables with a loop; use explicit resource cleanup. |
| 8 | `make_sensor_space_schematic_brain_figure.m` | Calculate the illustrative marker and its colours one surface vertex at a time; use explicit cleanup. |
| 9 | `make_source_reconstruction_report.m` | Calculate sensor-to-mesh distances with nested loops; check coordinate validity with explicit conditions; use clearer EEG/geometry variable names. |
| 10 | `Results_of_DCM_ERP.m` | Calculate each PEB group effect, posterior uncertainty, and group prediction separately; count retained effects with loops; calculate fitted-space R2 by mode and time point; expand compressed instructions and rename short variables. |
| 11 | `DCM_ERP_Two_Brain_Figures.m` | Find the nearest display vertex with a loop; select retained edges with `for`/`if`; construct each curved arrow point separately. |
| 12 | `make_BrainNet_DCM_ERP_files.m` | Replace `accumarray` with a pair-counting loop; use ordinary loops and conditions for directed edge matrices. |

The filenames and callable function names have been retained. Short variables were renamed where that did not change an external file interface. Required names such as `T`, `NodeTable`, `cfg`, and `tE1_clean` remain compatible with the saved files and downstream scripts.

There is also a small file named `make_dcm_erp_results_report.m`. In the retrieved source files, its implementation was identical to `Results_of_DCM_ERP.m` after changing the function name. It is now a **compatibility wrapper**, calling the rewritten `Results_of_DCM_ERP`. These two names represent one report implementation, so the count is 12 implementations, not 13 separate analyses.

## Selecting the source versions

The latest retrieved revision of each filename was used. The duplicate DCM report was resolved in favour of `Results_of_DCM_ERP.m`, whose retrieved file timestamp was slightly later. `SOURCE_VERSIONS.csv` lists the source filenames, revision numbers, and timestamps. These are file-revision timestamps; they are not a reconstructed transcript of every chat message. A latest saved file is not, by itself, proof of a successful execution.

## How to use the files

1. Extract the ZIP into a new folder. Open that folder in MATLAB, or add it to the MATLAB path.
2. Use the MATLAB and SPM installation used for the original study. Check the data paths near the beginning of each relevant file. The existing project paths were retained.
3. Use the report or figure script needed for your current output. For already completed analyses, creating reports does not require rerunning the participant models.

The four batch/convolution launchers are **alternative routes**, not four consecutive processing stages:

- `run_batch1_all_subjects.m`: a saved MAT batch.
- `all_4_batch_corrected.m`: a saved four-module M-file batch.
- `run_convolution_all43_no_batch.m`: construct the convolution batch in code.
- `run_convolution_all43.m`: a saved convolution-only batch.

The earlier launchers were retained as distinct alternatives, rather than silently combining them. Their saved batch requirements and time-window behaviour were preserved. Select the route that matches the batch and workflow actually used in the study. This rewrite does not establish that a previously reported SPM batch execution error has been resolved.

`add_tE1_clean_to_all43.m` appends the clean onset vector to the participant MAT headers. It retains the existing backup behaviour. The convolution scripts also calculate their own onset vectors.

The GLM report retains `study.wordOnlyFromSavedResults = true`, as in the last retrieved version. In that mode it reads the existing report archive to recreate Word tables. Set it to `false` when intentionally rebuilding the complete report from the participant data.

For the DCM report and its two later figure/export functions, use:

```matlab
reportFolder = Results_of_DCM_ERP;
reportFile = fullfile(reportFolder, 'Extracted_Report_Values.mat');

brainFigureFolder = DCM_ERP_Two_Brain_Figures(reportFile);
brainNetFolder = make_BrainNet_DCM_ERP_files(reportFile, false);
```

Use `Results_of_DCM_ERP` or its compatibility name once; there is no need to run both.

## Analysis details retained

- Final participant manifest: 20 monolingual and 23 bilingual participants; subject 17 remains excluded.
- The saved study settings, existing group codes, numerical thresholds, and output variable names were preserved.
- PEB differences still use the actual difference between the saved group codes. Group posterior uncertainty still includes intercept-slope covariance.
- The retention rule remains strictly `Pp > 0.95`; this is not a frequentist p-value or a posterior probability of a positive sign.
- The source-reconstruction report still inspects head-model preparation. It does not perform a new distributed source inversion.
- Sensor-space schematic markers remain illustrative. Original DCM MNI priors remain unchanged; display adjustments remain separate from those priors.

The comments and code explanations are English. Persian strings that form the original thesis table labels or reporting text were retained because they are report content, rather than code comments.

## Verification

All 12 rewritten files and the compatibility wrapper were checked with a MATLAB syntax parser. The study settings and saved/loaded variable interfaces were compared with the source versions. Every comment was checked for the English-only requirement.

Synthetic numerical comparisons checked E1 boundary rules, PEB effects and group uncertainty, fitted-space R2, descriptive Welch equations, and directed edge indexing. These checks passed. Explicit summation can produce negligible floating-point rounding differences.

**No MATLAB/SPM execution on the actual participant data was performed.** The syntax and numerical checks are not a claim that the complete workflow has been rerun successfully. See `VALIDATION.txt` for the recorded checks and `REWRITE_MANIFEST.json` for the per-file changes and hashes.
