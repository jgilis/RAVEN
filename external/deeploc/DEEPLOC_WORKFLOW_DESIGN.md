# DeepLoc-2.1 Integration - Simplified Workflow Design

## Overview
This design integrates DeepLoc-2.1 into RAVEN by creating a simple workflow that leverages existing RAVEN functions. The workflow is:

**FASTA file → `deeplocRun.m` → CSV file → `parseScores('deeploc')` → GSS → `predictLocalization.m`**

---

## Workflow Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  User Workflow                                              │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│  1. deeplocRun.m (external/deeploc/)                        │
│     - Accepts FASTA file path                               │
│     - Submits to DeepLoc webserver                          │
│     - Downloads CSV results                                 │
│     - Returns CSV file path                                 │
└───────────────────┬─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────────────────┐
│  2. parseScores.m (external/) - EXISTING FUNCTION           │
│     - Parses CSV with 'deeploc' option                      │
│     - Creates GSS structure                                 │
└───────────────────┬─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────────────────┐
│  3. predictLocalization.m (core/) - EXISTING FUNCTION       │
│     - Uses GSS to predict reaction compartmentalization     │
└─────────────────────────────────────────────────────────────┘
```

**Optional Helper:**
```
┌─────────────────────────────────────────────────────────────┐
│  deeplocFormatSequences.m (external/deeploc/) - OPTIONAL    │
│     - Prepares/validates FASTA file if needed               │
└─────────────────────────────────────────────────────────────┘
```

---

## Function Specifications

### 1. `external/deeploc/deeplocRun.m` (Main Function)

**Purpose:** Submit FASTA sequences to DeepLoc-2.1 webserver and download CSV results.

**Function Signature:**
```matlab
function csvFilePath = deeplocRun(fastaFilePath, varargin)
```

**Input Parameters:**
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `fastaFilePath` | char | Yes | Path to FASTA file containing protein sequences |
| `'Mode'` | char | No | Prediction mode: 'fast' (default) or 'high-quality' |
| `'Figures'` | logical | No | Request figures from DeepLoc (default: false) |
| `'Email'` | char | No | Email address for notification (optional, default: '') |
| `'OutputDir'` | char | No | Directory to save CSV file (optional, default: current directory) |
| `'Timeout'` | double | No | HTTP request timeout in seconds (optional, default: 600) |
| `'Verbose'` | logical | No | Print progress messages (optional, default: true) |
| `'BaseURL'` | char | No | DeepLoc webserver URL (optional, default: to be determined) |

**Output:**
| Output | Type | Description |
|--------|------|-------------|
| `csvFilePath` | char | Full path to downloaded CSV file |

**Internal Workflow:**
1. Validate FASTA file exists using `checkFileExistence()`
2. Read FASTA file to validate format
3. Construct POST request parameters:
   - Upload FASTA file or paste sequences
   - Set mode ('fast' or 'high-quality')
   - Set figures option (true/false)
   - Set email if provided
4. Submit POST request to DeepLoc webserver
5. Wait for job completion (polling or wait for response)
6. Download CSV results file
7. Save CSV to specified output directory
8. Return path to CSV file

**Error Handling:**
- Validate FASTA file exists and is readable
- Handle network timeouts
- Handle HTTP errors
- Handle job submission failures
- Handle CSV download failures
- Provide informative error messages using `dispEM()`

**Dependencies:**
- `checkFileExistence()` - RAVEN function for file validation
- `findRAVENroot()` - RAVEN function to locate installation
- `dispEM()` - RAVEN function for error messages
- MATLAB's `webwrite()` or `urlread()` for HTTP requests
- MATLAB's file I/O functions

---

### 2. `external/deeploc/deeplocFormatSequences.m` (Optional Helper)

**Purpose:** Prepare or validate FASTA file format if needed before submission.

**Function Signature:**
```matlab
function [validatedFastaPath, isValid] = deeplocFormatSequences(fastaFilePath, varargin)
```

**Input Parameters:**
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `fastaFilePath` | char | Yes | Path to FASTA file to validate/prepare |
| `'OutputPath'` | char | No | Path for output file (optional, default: create temp file) |
| `'RemoveGaps'` | logical | No | Remove gap characters ('-') from sequences (default: true) |
| `'Validate'` | logical | No | Validate amino acid sequences (default: true) |
| `'FixHeaders'` | logical | No | Fix/standardize FASTA headers (default: false) |

**Output:**
| Output | Type | Description |
|--------|------|-------------|
| `validatedFastaPath` | char | Path to validated/prepared FASTA file |
| `isValid` | logical | True if input file is valid (no changes needed) |

**Internal Workflow:**
1. Read FASTA file
2. Validate sequences (check for valid amino acids)
3. Remove gaps if requested
4. Fix headers if requested
5. Write validated FASTA to output path
6. Return path and validation status

**Note:** This function is optional. Users can use it if they need to prepare/validate FASTA files, but `deeplocRun.m` should work with standard FASTA files directly.

---

## Expected CSV Format (for parseScores compatibility)

Based on `parseScores.m` lines 90-110, the CSV format expected is:

**Header line:**
```
Column1,Column2,Column3,Compartment1,Compartment2,Compartment3,...
```

**Data rows:**
```
GeneName,Value1,Value2,Score1,Score2,Score3,...
```

Where:
- Column 1: Gene/Protein identifier
- Columns 2-3: Additional data (ignored by parseScores)
- Columns 4+: Compartment scores (one per compartment)

**Example:**
```csv
Sequence,Localization,Score,Cytoplasm,Nucleus,Mitochondrion,...
gene1,Localization1,0.95,0.85,0.10,0.05,...
gene2,Localization2,0.92,0.12,0.88,0.00,...
```

---

## Usage Examples

### Basic Workflow
```matlab
% Step 1: Run DeepLoc and get CSV
csvFile = deeplocRun('proteins.fasta');

% Step 2: Parse CSV to get GSS structure
GSS = parseScores(csvFile, 'deeploc');

% Step 3: Use GSS with predictLocalization
[model, geneLocalization, transportStruct, scores, removedRxns] = ...
    predictLocalization(model, GSS, 'Cytoplasm', 0.5, 15, false);
```

### With Options
```matlab
% Run DeepLoc with high-quality mode
csvFile = deeplocRun('proteins.fasta', ...
    'Mode', 'high-quality', ...
    'Figures', true, ...
    'Email', 'user@example.com', ...
    'OutputDir', './results', ...
    'Verbose', true);

% Parse and use
GSS = parseScores(csvFile, 'deeploc');
[model, geneLocalization, transportStruct, scores, removedRxns] = ...
    predictLocalization(model, GSS, 'Cytoplasm');
```

### With Optional FASTA Preparation
```matlab
% Prepare FASTA file first (optional)
[validatedFasta, isValid] = deeplocFormatSequences('raw_sequences.fasta', ...
    'RemoveGaps', true, ...
    'Validate', true);

% Run DeepLoc
csvFile = deeplocRun(validatedFasta, 'Mode', 'high-quality');

% Parse and use
GSS = parseScores(csvFile, 'deeploc');
[model, geneLocalization, transportStruct, scores, removedRxns] = ...
    predictLocalization(model, GSS, 'Cytoplasm');
```

---

## Implementation Notes

### DeepLoc-2.1 Webserver Research Required

Before implementation, research:
1. **Webserver URL:** Actual DeepLoc-2.1 endpoint
2. **Submission method:** 
   - File upload vs. paste sequences
   - Form field names
   - Required/optional parameters
3. **Response handling:**
   - Immediate response vs. job queue
   - Polling mechanism if async
   - CSV download method (direct link, email, etc.)
4. **CSV format:** Verify actual CSV format matches expected format

### Key Implementation Considerations

1. **File Upload vs. Paste:**
   - DeepLoc may accept file upload or require pasting sequences
   - If paste required, read FASTA and format as string
   - If upload, use multipart form data

2. **Async vs. Sync:**
   - If DeepLoc uses job queue, implement polling
   - Check job status periodically
   - Download results when ready

3. **CSV Download:**
   - May be direct download link in response
   - May require separate request with job ID
   - May be sent via email (if email provided)

4. **Error Handling:**
   - Network failures
   - Invalid FASTA format
   - Job submission failures
   - Timeout handling
   - Invalid CSV format

---

## Testing Strategy

### Unit Tests

**`deeplocRun.m`:**
- Test with valid FASTA file
- Test with different modes
- Test with various options
- Test error handling (invalid file, network errors, timeouts)
- Test CSV download and file saving

**`deeplocFormatSequences.m` (if implemented):**
- Test with valid FASTA
- Test with invalid sequences
- Test gap removal
- Test header fixing

### Integration Tests

- Full workflow: FASTA → CSV → GSS → predictLocalization
- Test with real RAVEN model
- Test with various FASTA file sizes
- Test error recovery

---

## Dependencies

### RAVEN Functions (Existing)
- `checkFileExistence()` - File validation
- `findRAVENroot()` - Locate RAVEN installation
- `dispEM()` - Error messages
- `parseScores()` - CSV parsing (with 'deeploc' option)
- `predictLocalization()` - Model compartmentalization

### MATLAB Functions
- `webwrite()` (R2014b+) or `urlread()` (older) - HTTP requests
- `fastaread()` (Bioinformatics Toolbox) or custom reader - FASTA reading
- Standard file I/O functions

### External
- Internet connection
- DeepLoc-2.1 webserver availability

---

## File Structure

```
external/
  └── deeploc/
      ├── deeplocRun.m              (REQUIRED - main function)
      ├── deeplocFormatSequences.m  (OPTIONAL - helper function)
      └── README.md                 (optional - usage documentation)
```

---

## Next Steps

1. **Research DeepLoc-2.1 API:**
   - Visit webserver and test manually
   - Document submission process
   - Document response format
   - Document CSV format

2. **Implement `deeplocRun.m`:**
   - Start with basic submission
   - Add CSV download
   - Add error handling
   - Add options support

3. **Implement `deeplocFormatSequences.m` (optional):**
   - Only if needed for FASTA preparation
   - Keep simple and focused

4. **Test Integration:**
   - Test with `parseScores('deeploc')`
   - Test with `predictLocalization()`
   - Verify end-to-end workflow

---

End of Design Document

