function [csvFilePath, pollURL] = deeplocRun(fastaFilePath, varargin)
% deeplocRun
%   Submits protein sequences from a FASTA file to DeepLoc-2.1 webserver
%   and downloads the resulting CSV file with localization predictions.
%
% Input:
%   fastaFilePath     path to FASTA file containing protein sequences
%   'Mode'            prediction mode: 'high-quality' (default) or 'fast'
%                     (optional)
%   'Figures'         true if figures should be requested from DeepLoc
%                     (optional, default false)
%   'Email'           email address for notification when job completes
%                     (optional, default: no email)
%   'OutputDir'       directory to save CSV file (optional, default: same
%                     directory as FASTA file)
%   'Timeout'         HTTP request timeout in seconds (optional, default 600)
%   'Verbose'         true if progress messages should be printed (optional,
%                     default true)
%   'BaseURL'         DeepLoc webserver base URL (optional, default:
%                     'https://services.healthtech.dtu.dk/services/DeepLoc-2.1')
%
% Output:
%   csvFilePath       full path to downloaded CSV file with DeepLoc results
%   pollURL           URL to check job status on DeepLoc webserver
%
% Usage:
%   [csvFile, pollURL] = deeplocRun('proteins.fasta');
%   [csvFile, pollURL] = deeplocRun('proteins.fasta', 'Mode', 'fast', ...
%       'Figures', true, 'Email', 'user@example.com');
%
% NOTE: This function requires internet connection to access DeepLoc-2.1
% webserver. The CSV file format must be compatible with parseScores.m
% using the 'deeploc' option.
%
% The workflow is:
%   1. deeplocRun() → CSV file
%   2. parseScores(CSV, 'deeploc') → GSS structure
%   3. predictLocalization(model, GSS, ...) → compartmentalized model

% Parse optional parameters
p = inputParser;
addParameter(p, 'Mode', 'high-quality', @(x) ischar(x) || isstring(x));
addParameter(p, 'Figures', false, @islogical);
addParameter(p, 'Email', '', @(x) ischar(x) || isstring(x) || isempty(x));
addParameter(p, 'OutputDir', '', @(x) ischar(x) || isstring(x) || isempty(x));  % Will be set to FASTA directory if empty
addParameter(p, 'Timeout', 600, @isnumeric);
addParameter(p, 'Verbose', true, @islogical);
addParameter(p, 'BaseURL', 'https://services.healthtech.dtu.dk/services/DeepLoc-2.1', @(x) ischar(x) || isstring(x));
parse(p, varargin{:});

mode = char(p.Results.Mode);
figures = p.Results.Figures;
email = char(p.Results.Email);
outputDir = char(p.Results.OutputDir);
timeout = p.Results.Timeout;
verbose = p.Results.Verbose;
baseURL = char(p.Results.BaseURL);

% Validate mode
if ~ismember(lower(mode), {'fast', 'high-quality'})
    EM = 'Mode must be either ''fast'' or ''high-quality''';
    dispEM(EM, true);
end

% Normalize inputs
fastaFilePath = convertCharArray(fastaFilePath);
if numel(fastaFilePath) > 1
    EM = 'Only one FASTA file can be submitted at a time';
    dispEM(EM, true);
end
fastaFilePath = fastaFilePath{1};

% Validate FASTA file exists
fastaFilePath = checkFileExistence(fastaFilePath, 1);

% Set default output directory to FASTA file directory if not specified
if isempty(outputDir)
    [fastaDir, ~, ~] = fileparts(fastaFilePath);
    outputDir = fastaDir;
end

% Validate output directory
if ~isfolder(outputDir)
    try
        mkdir(outputDir);
    catch
        EM = sprintf('Cannot create output directory: %s', outputDir);
        dispEM(EM, true);
    end
end

% Read and validate FASTA file
if verbose
    fprintf('Reading FASTA file: %s\n', fastaFilePath);
end

% Try to read FASTA file to validate format
try
    % Try using fastaread if Bioinformatics Toolbox is available
    if exist('fastaread', 'file') == 2
        sequences = fastaread(fastaFilePath);
        if isempty(sequences)
            EM = 'FASTA file appears to be empty';
            dispEM(EM, true);
        end
        if verbose
            fprintf('  Found %d sequence(s)\n', numel(sequences));
        end
    else
        % Simple validation: check if file contains '>' characters
        fid = fopen(fastaFilePath, 'r');
        if fid == -1
            EM = sprintf('Cannot open FASTA file: %s', fastaFilePath);
            dispEM(EM, true);
        end
        content = fread(fid, '*char')';
        fclose(fid);
        if ~contains(content, '>')
            EM = 'FASTA file does not appear to contain valid FASTA format (no headers starting with ''>'')';
            dispEM(EM, false);
        end
    end
catch ME
    EM = sprintf('Error reading FASTA file: %s', ME.message);
    dispEM(EM, true);
end

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
if isempty(urlParts)
    EM = sprintf('Invalid baseURL format: %s', baseURL);
    dispEM(EM, true);
end
domainRoot = urlParts{1};
submitURL = [domainRoot '/cgi-bin/webface2.cgi'];

if verbose
    fprintf('Submitting to DeepLoc-2.1...\n');
    fprintf('  Mode: %s (encode=%s)\n', mode, encodeMode);
    fprintf('  Format: %s\n', formatMode);
end

% ============================================================================
% STEP 1: Manually construct multipart/form-data body
% ============================================================================
if verbose
    fprintf('  Step 1: Preparing multipart form data...\n');
end

% Hard-coded form fields (stable, from browser-captured request)
configfile = '/var/www/services/services/DeepLoc-2.1/webface.cf';

% Read FASTA file as binary
fid = fopen(fastaFilePath, 'rb');
if fid == -1
    EM = sprintf('Cannot open FASTA file for reading: %s', fastaFilePath);
    dispEM(EM, true);
end
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
end

% ============================================================================
% STEP 2: Submit POST request and capture 302 redirect with jobid
% ============================================================================
if verbose
    fprintf('  Step 2: Submitting POST request to: %s\n', submitURL);
end

% Use matlab.net.http to send POST and capture 302 redirect headers
% (webwrite doesn't expose headers, so we need this for redirect handling)
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

try
    % Send request
    [response, ~, ~] = request.send(URI(submitURL), httpOptions);
    
    if verbose
        fprintf('    POST request completed (status: %d)\n', response.StatusCode);
    end
    
    % Check for 302 redirect
    if response.StatusCode == 302
        % Extract Location header
        locationFields = response.getFields('Location');
        if isempty(locationFields)
            EM = 'Received 302 redirect but no Location header found';
            dispEM(EM, true);
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
            EM = sprintf('Could not extract jobid from redirect Location header. URL: %s', locationURL);
            dispEM(EM, true);
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
        
        if contains(responseBody, 'Jobid not provided', 'IgnoreCase', true) || ...
           contains(responseBody, 'WebfaceConfigError', 'IgnoreCase', true)
            EM = sprintf('Server returned error (status %d): %s', response.StatusCode, responseBody);
            dispEM(EM, true);
        else
            EM = sprintf('Unexpected response status: %d (expected 302 redirect)', response.StatusCode);
            dispEM(EM, true);
        end
    end
    
catch ME
    EM = sprintf('Error submitting POST request to DeepLoc: %s', ME.message);
    dispEM(EM, true);
end

% Ensure jobId and waitTime variables exist
if ~exist('jobId', 'var') || isempty(jobId)
    EM = 'Could not extract jobid from server response';
    dispEM(EM, true);
end
if ~exist('waitTime', 'var')
    waitTime = 20;  % Default wait time if not extracted from redirect
end

% ============================================================================
% STEP 3: Poll for job completion using jobid
% ============================================================================
if verbose
    fprintf('  Step 3: Polling for job completion...\n');
end

% Construct polling URL (needed for output even if polling fails)
pollURL = [domainRoot '/cgi-bin/webface2.cgi?jobid=' jobId '&wait=' num2str(waitTime)];

% Submit email notification if provided
if ~isempty(email)
    if verbose
        fprintf('  Submitting email notification: %s\n', email);
    end
    
    try
        % URL-encode the email address
        % Use Java URLEncoder for proper encoding (e.g., @ becomes %40)
        if exist('java.net.URLEncoder', 'class') == 8
            emailEncoded = char(java.net.URLEncoder.encode(email, 'UTF-8'));
        else
            % Fallback: manual encoding for common characters
            emailEncoded = email;
            emailEncoded = strrep(emailEncoded, '@', '%40');
            emailEncoded = strrep(emailEncoded, '+', '%2B');
            emailEncoded = strrep(emailEncoded, ' ', '%20');
        end
        
        % Construct email submission URL
        emailURL = [pollURL '&email=' emailEncoded '&submit=Send+email'];
        
        % Submit email via GET request (silent, don't need response)
        webread(emailURL, weboptions('Timeout', timeout));
        
        if verbose
            fprintf('    Email notification submitted successfully\n');
        end
    catch ME
        % Don't fail the whole process if email submission fails
        if verbose
            fprintf('    Warning: Could not submit email notification: %s\n', ME.message);
        end
    end
end

% Poll until CSV is available
maxPollTime = timeout;
pollInterval = waitTime;  % Use the wait time from server
elapsedTime = 0;
csvURL = '';
pollCount = 0;

while elapsedTime < maxPollTime && isempty(csvURL)
    pollCount = pollCount + 1;
    if verbose
        fprintf('    Polling job status (attempt %d, elapsed: %d seconds)...\n', pollCount, elapsedTime);
    end
    
    try
        % Use webread to poll (simpler than matlab.net.http for GET)
        pollHtml = webread(pollURL, weboptions('Timeout', timeout));
        
        % Ensure pollHtml is char (webread may return string)
        if isstring(pollHtml)
            pollHtml = char(pollHtml);
        end
        
        % Check if job is complete and construct CSV URL directly from job ID
        % The CSV URL follows a predictable pattern: /services/DeepLoc-2.1/tmp/{jobId}/results_{jobId}.csv
        % Once the results page is available, the CSV can be downloaded at this URL
        csvURL = '';
        jobComplete = false;
        completionIndicator = '';
        
        % Check for indicators that the job is complete (results page is displayed)
        
        % Check for completion indicators (case-insensitive)
        if contains(pollHtml, 'Download prediction results', 'IgnoreCase', true)
            jobComplete = true;
            completionIndicator = 'Download prediction results';
        elseif contains(pollHtml, 'CSV Summary', 'IgnoreCase', true)
            jobComplete = true;
            completionIndicator = 'CSV Summary';
        elseif contains(pollHtml, 'predicted sequences', 'IgnoreCase', true)
            jobComplete = true;
            completionIndicator = 'predicted sequences';
        elseif contains(pollHtml, 'Finished prediction', 'IgnoreCase', true)
            jobComplete = true;
            completionIndicator = 'Finished prediction';
        end
        
        if jobComplete
            % Job is complete - construct CSV URL directly from job ID
            csvURL = [baseURL '/tmp/' jobId '/results_' jobId '.csv'];
            if verbose
                fprintf('    Detected job completion: Found "%s"\n', completionIndicator);
                fprintf('    Constructed CSV URL from job ID: %s\n', csvURL);
            end
        end
        
        if ~isempty(csvURL)
            if verbose
                fprintf('    Job completed! CSV URL: %s\n', csvURL);
            end
            break;
        end
        
        % Wait before next poll
        pause(pollInterval);
        elapsedTime = elapsedTime + pollInterval;
        
    catch ME
        EM = sprintf('Error polling job status: %s', ME.message);
        dispEM(EM, false);  % Warning, continue polling
        pause(pollInterval);
        elapsedTime = elapsedTime + pollInterval;
    end
end

if isempty(csvURL)
    EM = sprintf('Job did not complete within timeout (%d seconds). Job ID: %s', timeout, jobId);
    if verbose
        fprintf('\n');
        fprintf('  Job ID: %s\n', jobId);
        fprintf('  Number of polling attempts: %d\n', pollCount);
        fprintf('  You can manually check the job status by visiting:\n');
        fprintf('    %s\n', pollURL);
    end
    dispEM(EM, true);
end

% ============================================================================
% STEP 4: Download CSV file
% ============================================================================
if verbose
    fprintf('  Step 4: Downloading CSV file: %s\n', csvURL);
end

try
    % Use webread to download CSV
    % Note: webread may automatically parse CSV into a table, so we need to handle that
    csvContent = webread(csvURL, weboptions('Timeout', timeout));
    
    % webread may automatically parse CSV into a table, so handle that case
    if istable(csvContent)
        % Convert table back to CSV string format
        tempFile = [tempname '.csv'];
        writetable(csvContent, tempFile);
        csvContent = fileread(tempFile);
        delete(tempFile);
    elseif isstring(csvContent)
        csvContent = char(csvContent);
    end
    
    if verbose
        fprintf('    CSV file downloaded (%d characters)\n', length(csvContent));
    end
catch ME
    EM = sprintf('Error downloading CSV file: %s', ME.message);
    dispEM(EM, true);
end

% Generate output filename
[~, fastaName, ~] = fileparts(fastaFilePath);
timestamp = datestr(now, 'yyyymmdd_HHMMSS');
csvFilename = sprintf('deeploc_%s_%s.csv', fastaName, timestamp);
csvFilePath = fullfile(outputDir, csvFilename);

% Save CSV file
if verbose
    fprintf('Saving CSV file: %s\n', csvFilePath);
end

try
    fid = fopen(csvFilePath, 'w');
    if fid == -1
        EM = sprintf('Cannot create CSV file: %s', csvFilePath);
        dispEM(EM, true);
    end
    fprintf(fid, '%s', csvContent);
    fclose(fid);
catch ME
    EM = sprintf('Error saving CSV file: %s', ME.message);
    dispEM(EM, true);
end

if verbose
    fprintf('Success! CSV file saved to: %s\n', csvFilePath);
end

% Return pollURL as second output
% pollURL is already defined from the polling loop

end
