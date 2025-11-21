# DeepLoc-2.1 Integration for RAVEN Toolbox

## Overview

This module provides integration with DeepLoc-2.1 webserver for protein subcellular localization prediction. The results are automatically formatted for use with RAVEN's `predictLocalization()` function.

## Workflow

```
FASTA file → deeplocRun.m → CSV file → parseScores('deeploc') → GSS → predictLocalization.m
```

## Quick Start

```matlab
% Step 1: Run DeepLoc and get CSV results
csvFile = deeplocRun('proteins.fasta');

% Step 2: Parse CSV to get GSS structure
GSS = parseScores(csvFile, 'deeploc');

% Step 3: Use GSS with predictLocalization
[model, geneLocalization, transportStruct, scores, removedRxns] = ...
    predictLocalization(model, GSS, 'Cytoplasm', 0.5, 15, false);
```

## Functions

### `deeplocRun.m`

Main function that submits FASTA sequences to DeepLoc-2.1 and downloads CSV results.

**Usage:**
```matlab
csvFile = deeplocRun('proteins.fasta');
csvFile = deeplocRun('proteins.fasta', 'Mode', 'high-quality', 'Figures', true);
```

**Options:**
- `'Mode'` - 'fast' (default) or 'high-quality'
- `'Figures'` - true/false (default: false) - request figures from DeepLoc
- `'Email'` - email address for notification when job completes (optional)
- `'OutputDir'` - directory to save CSV file (default: current directory)
- `'Timeout'` - HTTP request timeout in seconds (default: 600)
- `'Verbose'` - print progress messages (default: true)
- `'BaseURL'` - DeepLoc webserver base URL (default: 'https://services.healthtech.dtu.dk/services/DeepLoc-2.1')

**Output:**
- `csvFilePath` - full path to downloaded CSV file with DeepLoc results

## Requirements

- Internet connection (for DeepLoc-2.1 webserver)
- MATLAB R2023b or later (uses `matlab.net.http` package)
- RAVEN Toolbox installed

## How It Works

1. **Submission**: Reads FASTA file and submits it to DeepLoc-2.1 webserver via HTTP POST
2. **Job Tracking**: Captures job ID from server redirect response
3. **Polling**: Polls job status until completion is detected
4. **Download**: Constructs CSV URL from job ID and downloads results
5. **Output**: Saves CSV file to specified output directory

## Debugging

For debugging purposes, you can use `deeplocRun_Debug.m` which breaks down the function into step-by-step sections that can be run interactively.

Debug files (polling responses) are saved to: `tempdir()/deeploc_debug/`

## Notes

- The CSV format is compatible with `parseScores.m` using the 'deeploc' option
- This module does not modify any core RAVEN functions
- DeepLoc-2.1 results page uses AngularJS templates, so the CSV URL is constructed from the job ID rather than parsed from HTML

## Example

```matlab
% Submit sequences and get results
csvFile = deeplocRun('my_proteins.fasta', 'Mode', 'fast', 'Verbose', true);

% Parse results into GSS structure
GSS = parseScores(csvFile, 'deeploc');

% Use with predictLocalization
model = predictLocalization(model, GSS, 'Cytoplasm', 0.5, 15, false);
```
