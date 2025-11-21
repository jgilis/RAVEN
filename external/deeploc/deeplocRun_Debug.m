%% DeepLoc Run - Interactive Debug Script
% This script allows you to run deeplocRun.m step by step for debugging
% 
% Instructions:
% 1. Set the fastaFilePath variable below to your FASTA file
% 2. Run each section sequentially using Ctrl+Enter (or select and run)
% 3. Inspect variables in the workspace between sections
%
% To convert this to a Live Script (.mlx):
% - Open this file in MATLAB
% - Go to: Editor > Save > Save As > Change file type to "MATLAB Live Code Files (*.mlx)"

%% Setup: Configure Parameters
% Set your FASTA file path here
fastaFilePath = '../../temp/seqs_added_short.faa';

% Optional parameters (modify as needed)
mode = 'fast';              % 'fast' or 'high-quality'
figures = false;            % true to request figures
email = '';                 % email for notification (optional)
outputDir = pwd;            % output directory
timeout = 600;              % timeout in seconds
verbose = true;             % show progress messages
baseURL = 'https://services.healthtech.dtu.dk/services/DeepLoc-2.1';

%% Step 1: Input Validation and Setup
% This section validates inputs and sets up variables

% Normalize inputs
fastaFilePath = convertCharArray(fastaFilePath);
if numel(fastaFilePath) > 1
    error('Only one FASTA file can be submitted at a time');
end
fastaFilePath = fastaFilePath{1};

% Validate FASTA file exists
fastaFilePath = checkFileExistence(fastaFilePath, 1);

% Validate output directory
if ~isfolder(outputDir)
    mkdir(outputDir);
end

% Read and validate FASTA file
if verbose
    fprintf('Reading FASTA file: %s\n', fastaFilePath);
end

% Try to read FASTA file to validate format
if exist('fastaread', 'file') == 2
    sequences = fastaread(fastaFilePath);
    if isempty(sequences)
        error('FASTA file appears to be empty');
    end
    if verbose
        fprintf('  Found %d sequence(s)\n', numel(sequences));
    end
else
    % Simple validation: check if file contains '>' characters
    fid = fopen(fastaFilePath, 'r');
    content = fread(fid, '*char')';
    fclose(fid);
    if ~contains(content, '>')
        warning('FASTA file does not appear to contain valid FASTA format');
    end
end

%% Step 2: Map Parameters to DeepLoc Values
% Map mode parameter to DeepLoc values
if strcmpi(mode, 'fast')
    encodeMode = 'Fast';
else
    encodeMode = 'Slow';  % 'high-quality' maps to 'Slow'
end

% Map figures parameter to DeepLoc format values
if figures
    formatMode = 'long';
else
    formatMode = 'short';
end

% Construct submission URL
urlParts = regexp(baseURL, '^(https?://[^/]+)', 'tokens', 'once');
domainRoot = urlParts{1};
submitURL = [domainRoot '/cgi-bin/webface2.cgi'];

if verbose
    fprintf('Submitting to DeepLoc-2.1...\n');
    fprintf('  Mode: %s (encode=%s)\n', mode, encodeMode);
    fprintf('  Format: %s\n', formatMode);
end

%% Step 3: Construct Multipart Form Data
% This section manually constructs the multipart/form-data body

if verbose
    fprintf('  Step 1: Preparing multipart form data...\n');
end

% Hard-coded form fields (stable, from browser-captured request)
configfile = '/var/www/services/services/DeepLoc-2.1/webface.cf';

% Read FASTA file as binary
fid = fopen(fastaFilePath, 'rb');
fastaFileData = fread(fid, '*uint8')';  % Ensure row vector
fclose(fid);
% Ensure fastaFileData is a row vector
if size(fastaFileData, 1) > 1
    fastaFileData = fastaFileData';
end

% Get filename for upload
[~, fastaFileName, fastaExt] = fileparts(fastaFilePath);
if isempty(fastaExt)
    fastaExt = '.faa';
end
fastaFileNameFull = [fastaFileName fastaExt];

% Generate random boundary string
boundary = ['----MATLABFormBoundary', char(randi([65 90], 1, 16))];

% Build multipart body manually
% Each part: --boundary\r\nContent-Disposition: ...\r\n\r\n<data>\r\n
bodyParts = {};

% Part 1: configfile
bodyParts{end+1} = sprintf('--%s\r\n', boundary);
bodyParts{end+1} = sprintf('Content-Disposition: form-data; name="configfile"\r\n');
bodyParts{end+1} = sprintf('\r\n');
bodyParts{end+1} = sprintf('%s\r\n', configfile);

% Part 2: encode
bodyParts{end+1} = sprintf('--%s\r\n', boundary);
bodyParts{end+1} = sprintf('Content-Disposition: form-data; name="encode"\r\n');
bodyParts{end+1} = sprintf('\r\n');
bodyParts{end+1} = sprintf('%s\r\n', encodeMode);

% Part 3: format
bodyParts{end+1} = sprintf('--%s\r\n', boundary);
bodyParts{end+1} = sprintf('Content-Disposition: form-data; name="format"\r\n');
bodyParts{end+1} = sprintf('\r\n');
bodyParts{end+1} = sprintf('%s\r\n', formatMode);

% Part 4: uploadfile (binary file)
bodyParts{end+1} = sprintf('--%s\r\n', boundary);
bodyParts{end+1} = sprintf('Content-Disposition: form-data; name="uploadfile"; filename="%s"\r\n', fastaFileNameFull);
bodyParts{end+1} = sprintf('Content-Type: application/octet-stream\r\n');
bodyParts{end+1} = sprintf('\r\n');

% Closing boundary
bodyParts{end+1} = sprintf('--%s--\r\n', boundary);

% Convert all parts to uint8 and concatenate
bodyChar = [bodyParts{:}];
bodyUint8 = uint8(bodyChar);
% Ensure bodyUint8 is a row vector
if size(bodyUint8, 1) > 1
    bodyUint8 = bodyUint8';
end
% Insert binary file data before the closing boundary
% Find position of last boundary (before --boundary--)
closingBoundaryPos = length(bodyUint8) - length(sprintf('--%s--\r\n', boundary)) + 1;
% Ensure all parts are row vectors before concatenation
bodyUint8 = [bodyUint8(1:closingBoundaryPos-1), fastaFileData(:)', bodyUint8(closingBoundaryPos:end)];

if verbose
    fprintf('    Multipart body constructed (%d bytes)\n', length(bodyUint8));
    fprintf('    Boundary: %s\n', boundary);
end

% Inspect the body (first 500 bytes)
fprintf('\nFirst 500 bytes of multipart body:\n');
fprintf('%s\n', char(bodyUint8(1:min(500, length(bodyUint8)))));

%% Step 4: Submit POST Request
% This section sends the POST request and captures the 302 redirect

if verbose
    fprintf('  Step 2: Submitting POST request to: %s\n', submitURL);
end

% Import required packages
import matlab.net.*
import matlab.net.http.*
import matlab.net.http.field.*
import matlab.net.http.io.*

% Create headers
% Use row vector concatenation to avoid dimension mismatch
contentTypeHeader = GenericField('Content-Type', sprintf('multipart/form-data; boundary=%s', boundary));
userAgentHeader = GenericField('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36');
requestHeaders = [contentTypeHeader, userAgentHeader];  % Use comma (row vector) instead of semicolon

% Create request with body
% Convert uint8 to char (FASTA files are text, so this is safe)
% Wrap in MessageBody for proper handling
bodyChar = char(bodyUint8);
bodyMessage = MessageBody(bodyChar);
request = RequestMessage('POST', requestHeaders, bodyMessage);

% Set HTTP options to NOT follow redirects (we need to capture the 302)
httpOptions = HTTPOptions('MaxRedirects', 0, 'ConnectTimeout', timeout);

% Send request
[response, ~, ~] = request.send(URI(submitURL), httpOptions);

if verbose
    fprintf('    POST request completed (status: %d)\n', response.StatusCode);
end

%% Step 5: Extract Job ID from 302 Redirect
% This section extracts the jobid and wait time from the Location header

% Check for 302 redirect
if response.StatusCode == 302
    % Extract Location header
    locationFields = response.getFields('Location');
    if isempty(locationFields)
        error('Received 302 redirect but no Location header found');
    end
    
    % Get the Location header value (may be relative or absolute)
    locationURL = char(locationFields(1).Value);
    
    if verbose
        fprintf('    Location header value: %s\n', locationURL);
    end
    
    % Make absolute URL if relative
    if startsWith(locationURL, '/')
        locationURL = [domainRoot locationURL];
    elseif ~startsWith(locationURL, 'http')
        % If it doesn't start with http and isn't relative, prepend domain
        locationURL = [domainRoot '/' locationURL];
    end
    
    if verbose
        fprintf('    Full redirect URL: %s\n', locationURL);
    end
    
    % Parse jobid and wait value from Location URL
    % Format: /cgi-bin/webface2.cgi?jobid=XXXXXXXXXXXX&wait=20
    jobidPattern = '[?&]jobid=([^&]+)';
    jobidMatch = regexp(locationURL, jobidPattern, 'tokens', 'once');
    if isempty(jobidMatch)
        error('Could not extract jobid from redirect Location header. URL: %s', locationURL);
    end
    jobId = jobidMatch{1};
    
    waitPattern = '[?&]wait=(\d+)';
    waitMatch = regexp(locationURL, waitPattern, 'tokens', 'once');
    waitTime = 20;  % Default wait time
    if ~isempty(waitMatch)
        waitTime = str2double(waitMatch{1});
    end
    
    if verbose
        fprintf('    Extracted jobid: %s\n', jobId);
        fprintf('    Wait time: %d seconds\n', waitTime);
    end
    
else
    % Not a redirect - check for errors
    % Extract response body for error checking
    if isa(response.Body, 'matlab.net.http.MessageBody')
        bodyData = response.Body.Data;
        if isa(bodyData, 'uint8')
            responseBody = char(bodyData');
        else
            responseBody = char(bodyData);
        end
    else
        responseBody = char(response.Body);
    end
    
    error('Unexpected response status: %d\nResponse body: %s', response.StatusCode, responseBody);
end

%% Step 6: Poll for Job Completion
% This section polls the job status until the CSV is available

if verbose
    fprintf('  Step 3: Polling for job completion...\n');
end

% Construct polling URL
pollURL = [domainRoot '/cgi-bin/webface2.cgi?jobid=' jobId '&wait=' num2str(waitTime)];

% Poll until CSV is available
maxPollTime = timeout;
pollInterval = waitTime;  % Use the wait time from server
elapsedTime = 0;
csvURL = '';

while elapsedTime < maxPollTime && isempty(csvURL)
    if verbose
        fprintf('    Polling job status (elapsed: %d seconds)...\n', elapsedTime);
    end
    
    try
        % Use webread to poll (simpler than matlab.net.http for GET)
        pollHtml = webread(pollURL, weboptions('Timeout', timeout));
        
        % Extract CSV URL from response (using helper function from deeplocRun.m)
        % For debugging, you can inspect pollHtml here
        csvURL = extractCSVURL(pollHtml, baseURL, verbose);
        
        if ~isempty(csvURL)
            if verbose
                fprintf('    Job completed! CSV URL found: %s\n', csvURL);
            end
            break;
        end
        
        % Wait before next poll
        pause(pollInterval);
        elapsedTime = elapsedTime + pollInterval;
        
    catch ME
        warning('Error polling job status: %s', ME.message);
        pause(pollInterval);
        elapsedTime = elapsedTime + pollInterval;
    end
end

if isempty(csvURL)
    error('Job did not complete within timeout (%d seconds). Job ID: %s', timeout, jobId);
end

%% Step 7: Download CSV File
% This section downloads and saves the CSV file

if verbose
    fprintf('  Step 4: Downloading CSV file: %s\n', csvURL);
end

% Use webread to download CSV
csvContent = webread(csvURL, weboptions('Timeout', timeout));

% webread may return as char or string, ensure it's char
if isstring(csvContent)
    csvContent = char(csvContent);
end

if verbose
    fprintf('    CSV file downloaded (%d characters)\n', length(csvContent));
end

%% Step 8: Save CSV File
% This section saves the CSV to disk

% Generate output filename
[~, fastaName, ~] = fileparts(fastaFilePath);
timestamp = datestr(now, 'yyyymmdd_HHMMSS');
csvFilename = sprintf('deeploc_%s_%s.csv', fastaName, timestamp);
csvFilePath = fullfile(outputDir, csvFilename);

% Save CSV file
if verbose
    fprintf('Saving CSV file: %s\n', csvFilePath);
end

fid = fopen(csvFilePath, 'w');
fprintf(fid, '%s', csvContent);
fclose(fid);

if verbose
    fprintf('Success! CSV file saved to: %s\n', csvFilePath);
end

%% Helper Functions
% These functions are copied from deeplocRun.m for use in this debug script

function csvURL = extractCSVURL(htmlContent, baseURL, verbose)
    csvURL = '';
    
    % Strategy 1: Look for CSV URL pattern in HTML (most reliable)
    pattern = '(?:https?://[^"\s''<>]+)?/services/DeepLoc-2\.1/tmp/[^/"\s''<>]+/results_[^"\s''<>]+\.csv';
    matches = regexp(htmlContent, pattern, 'match');
    
    if ~isempty(matches)
        csvURL = matches{1};
        % Make absolute URL if relative
        if ~startsWith(csvURL, 'http')
            if startsWith(csvURL, '/')
                csvURL = ['https://services.healthtech.dtu.dk' csvURL];
            else
                csvURL = [baseURL '/' csvURL];
            end
        end
        if verbose
            fprintf('  Found CSV URL (pattern match): %s\n', csvURL);
        end
        return;
    end
    
    % Strategy 2: Look for direct CSV download links in <a> tags
    pattern = '<a[^>]*href=["'']([^"'']*results[^"'']*\.csv[^"'']*)["'']';
    matches = regexp(htmlContent, pattern, 'tokens', 'once');
    
    if ~isempty(matches)
        csvURL = matches{1};
        if contains(csvURL, '{{') || contains(csvURL, 'JSON')
            csvURL = extractCSVFromJSON(htmlContent, baseURL, verbose);
        else
            if ~startsWith(csvURL, 'http')
                if startsWith(csvURL, '/')
                    csvURL = ['https://services.healthtech.dtu.dk' csvURL];
                else
                    csvURL = [baseURL '/' csvURL];
                end
            end
            if verbose
                fprintf('  Found CSV URL in link: %s\n', csvURL);
            end
        end
        if ~isempty(csvURL)
            return;
        end
    end
    
    % Strategy 3: Try to extract from JSON data
    csvURL = extractCSVFromJSON(htmlContent, baseURL, verbose);
end

function csvURL = extractCSVFromJSON(htmlContent, baseURL, verbose)
    csvURL = '';
    
    % Look for JSON data in script tags
    pattern = '(?:var\s+)?JSON\s*=\s*(\{.*?\});';
    matches = regexp(htmlContent, pattern, 'tokens', 'once', 'dotexceptnewline');
    
    if ~isempty(matches)
        try
            jsonStr = matches{1};
            jsonStr = regexprep(jsonStr, '//.*?\n', '');
            jsonStr = regexprep(jsonStr, '/\*.*?\*/', '');
            jsonData = jsondecode(jsonStr);
            
            if isfield(jsonData, 'csv_file')
                csvURL = jsonData.csv_file;
                if ~startsWith(csvURL, 'http')
                    if startsWith(csvURL, '/')
                        csvURL = ['https://services.healthtech.dtu.dk' csvURL];
                    else
                        csvURL = [baseURL '/' csvURL];
                    end
                end
                if verbose
                    fprintf('  Extracted CSV URL from JSON object: %s\n', csvURL);
                end
                return;
            end
        catch
        end
    end
    
    % Direct regex extraction of csv_file field
    pattern = '["'']?csv_file["'']?\s*:\s*["'']([^"'']+)["'']';
    matches = regexp(htmlContent, pattern, 'tokens', 'once');
    
    if ~isempty(matches)
        csvURL = matches{1};
        if ~startsWith(csvURL, 'http')
            if startsWith(csvURL, '/')
                csvURL = ['https://services.healthtech.dtu.dk' csvURL];
            else
                csvURL = [baseURL '/' csvURL];
            end
        end
        if verbose
            fprintf('  Extracted CSV URL from JSON field: %s\n', csvURL);
        end
        return;
    end
    
    % Look for results_*.csv pattern
    pattern = 'results_[A-F0-9]{16}\.csv';
    matches = regexp(htmlContent, pattern, 'match', 'once');
    
    if ~isempty(matches)
        tmpPattern = '/services/DeepLoc-2\.1/tmp/[^/]+/';
        tmpMatch = regexp(htmlContent, tmpPattern, 'match', 'once');
        if ~isempty(tmpMatch)
            csvURL = ['https://services.healthtech.dtu.dk' tmpMatch matches];
            if verbose
                fprintf('  Constructed CSV URL from pattern: %s\n', csvURL);
            end
        end
    end
end

