%% DeepLocPro Run - Interactive Debug Script
% This script allows you to run deeplocproRun.m step by step for debugging
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
organismGroup = 'Any';           % 'Any', 'Archaea', 'Gram negative', or 'Gram positive'
figures = false;                 % true to request figures
email = '';                      % email for notification (optional)
outputDir = pwd;                 % output directory
timeout = 900;                   % timeout in seconds
verbose = true;                  % show progress messages

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

% Set default output directory to FASTA file directory if not specified
if isempty(outputDir)
    [fastaDir, ~, ~] = fileparts(fastaFilePath);
    outputDir = fastaDir;
end

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
    numSequences = numel(sequences);
    
    % Validate sequence count (max 500 for DeepLocPro)
    if numSequences > 500
        error('DeepLocPro accepts a maximum of 500 sequences. Your file contains %d sequences.', numSequences);
    end
    
    % Validate sequence lengths (10-6000 amino acids)
    shortSequences = [];
    longSequences = [];
    for i = 1:numSequences
        seqLen = length(sequences(i).Sequence);
        if seqLen < 10
            shortSequences = [shortSequences, i];
        elseif seqLen > 6000
            longSequences = [longSequences, i];
        end
    end
    
    if ~isempty(shortSequences)
        warning('Warning: %d sequence(s) shorter than 10 amino acids detected. DeepLocPro predictions may be inaccurate for these sequences.', length(shortSequences));
    end
    if ~isempty(longSequences)
        warning('Warning: %d sequence(s) longer than 6000 amino acids detected. DeepLocPro predictions may be inaccurate for these sequences.', length(longSequences));
    end
    
    if verbose
        fprintf('  Found %d sequence(s)\n', numSequences);
    end
else
    % Simple validation: check if file contains '>' characters
    fid = fopen(fastaFilePath, 'r');
    content = fread(fid, '*char')';
    fclose(fid);
    if ~contains(content, '>')
        warning('FASTA file does not appear to contain valid FASTA format');
    end
    
    % Count sequences by counting '>' characters
    numSequences = sum(content == '>');
    if numSequences > 500
        error('DeepLocPro accepts a maximum of 500 sequences. Your file appears to contain %d sequences.', numSequences);
    end
    if verbose
        fprintf('  Found %d sequence(s)\n', numSequences);
    end
end

%% Step 2: Map Parameters to DeepLocPro Values
% Map organism group to DeepLocPro values
validOrganismGroups = {'Any', 'Archaea', 'Gram negative', 'Gram positive'};
if ~ismember(organismGroup, validOrganismGroups)
    error('OrganismGroup must be one of: %s', strjoin(validOrganismGroups, ', '));
end

% Map organism group to DeepLocPro values (lowercase with underscores)
if strcmpi(organismGroup, 'Any')
    groupValue = 'any';
elseif strcmpi(organismGroup, 'Archaea')
    groupValue = 'archaea';
elseif strcmpi(organismGroup, 'Gram negative')
    groupValue = 'gram_negative';
elseif strcmpi(organismGroup, 'Gram positive')
    groupValue = 'gram_positive';
end

% Map figures parameter to format
if figures
    formatValue = 'long';
else
    formatValue = 'short';
end

% Construct baseURL for DeepLocPro
baseURL = 'https://services.healthtech.dtu.dk/services/DeepLocPro-1.0';

% Construct submission URL
urlParts = regexp(baseURL, '^(https?://[^/]+)', 'tokens', 'once');
domainRoot = urlParts{1};
submitURL = [domainRoot '/cgi-bin/webface2.cgi'];

if verbose
    fprintf('Submitting to DeepLocPro-1.0...\n');
    fprintf('  Organism group: %s (group=%s)\n', organismGroup, groupValue);
    fprintf('  Format: %s\n', formatValue);
end

%% Step 3: Read FASTA File Content
% Read FASTA file content for form submission (pasted sequences)
fid = fopen(fastaFilePath, 'r');
if fid == -1
    error('Cannot open FASTA file for reading: %s', fastaFilePath);
end
fastaTextContent = fread(fid, '*char')';
fclose(fid);
% Ensure fastaTextContent is a row vector
if size(fastaTextContent, 1) > 1
    fastaTextContent = fastaTextContent';
end

if verbose
    fprintf('  FASTA content read (%d characters)\n', length(fastaTextContent));
end

%% Step 4: Construct Multipart Form Data
% This section manually constructs the multipart/form-data body

if verbose
    fprintf('  Step 1: Preparing submission data...\n');
end

% Hard-coded form fields (stable, from browser-captured request)
configfile = '/var/www/services/services/DeepLocPro-1.0/webface.cf';

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

% Part 2: fasta (pasted sequences)
bodyParts{end+1} = sprintf('--%s\r\n', boundary);
bodyParts{end+1} = sprintf('Content-Disposition: form-data; name="fasta"\r\n');
bodyParts{end+1} = sprintf('\r\n');
% FASTA text content will be inserted here

% Part 3: uploadfile (empty file upload)
bodyParts{end+1} = sprintf('--%s\r\n', boundary);
bodyParts{end+1} = sprintf('Content-Disposition: form-data; name="uploadfile"; filename=""\r\n');
bodyParts{end+1} = sprintf('Content-Type: application/octet-stream\r\n');
bodyParts{end+1} = sprintf('\r\n');
bodyParts{end+1} = sprintf('\r\n');  % Empty field

% Part 4: group (organism group)
bodyParts{end+1} = sprintf('--%s\r\n', boundary);
bodyParts{end+1} = sprintf('Content-Disposition: form-data; name="group"\r\n');
bodyParts{end+1} = sprintf('\r\n');
bodyParts{end+1} = sprintf('%s\r\n', groupValue);

% Part 5: format
bodyParts{end+1} = sprintf('--%s\r\n', boundary);
bodyParts{end+1} = sprintf('Content-Disposition: form-data; name="format"\r\n');
bodyParts{end+1} = sprintf('\r\n');
bodyParts{end+1} = sprintf('%s\r\n', formatValue);

% Closing boundary
bodyParts{end+1} = sprintf('--%s--\r\n', boundary);

% Convert all parts to uint8 and concatenate
bodyChar = [bodyParts{:}];
bodyUint8 = uint8(bodyChar);
% Ensure bodyUint8 is a row vector
if size(bodyUint8, 1) > 1
    bodyUint8 = bodyUint8';
end

% Insert FASTA text content after the fasta field header
fastaHeader = sprintf('Content-Disposition: form-data; name="fasta"\r\n\r\n');
fastaHeaderPos = strfind(char(bodyUint8), fastaHeader);
if isempty(fastaHeaderPos)
    error('Error constructing multipart form: could not find fasta field position');
end
fastaInsertPos = fastaHeaderPos + length(fastaHeader);

% Convert FASTA text content to uint8
fastaTextUint8 = uint8(fastaTextContent);
if size(fastaTextUint8, 1) > 1
    fastaTextUint8 = fastaTextUint8';
end

% Insert FASTA text content
bodyUint8 = [bodyUint8(1:fastaInsertPos-1), fastaTextUint8, bodyUint8(fastaInsertPos:end)];

if verbose
    fprintf('    Data prepared for submission (%d bytes)\n', length(bodyUint8));
    fprintf('    Boundary: %s\n', boundary);
end

% Inspect the body (first 500 bytes)
fprintf('\nFirst 500 bytes of multipart body:\n');
fprintf('%s\n', char(bodyUint8(1:min(500, length(bodyUint8)))));

%% Step 5: Submit POST Request
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
contentTypeHeader = GenericField('Content-Type', sprintf('multipart/form-data; boundary=%s', boundary));
userAgentHeader = GenericField('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36');
requestHeaders = [contentTypeHeader, userAgentHeader];  % Use comma (row vector)

% Create request with body
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

%% Step 6: Extract Job ID from 302 Redirect
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

%% Step 7: Poll for Job Completion
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
        
        % Check if job is complete and extract CSV URL from HTML
        % DeepLocPro uses a date-time suffix in the CSV filename: results_YYYYMMDD-HHMMSS.csv
        csvURL = '';
        jobComplete = false;
        completionIndicator = '';
        
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
            % Job is complete - extract CSV URL from HTML
            % Try multiple patterns to find the CSV download link
            
            % Pattern 1: Look for CSV URL with date-time pattern
            csvPattern = ['/services/DeepLocPro-1\.0/tmp/' jobId '/results_\d{8}-\d{6}\.csv'];
            csvMatches = regexp(pollHtml, csvPattern, 'match', 'once');
            if ~isempty(csvMatches)
                csvURL = csvMatches;
                % Make absolute URL if relative
                if ~startsWith(csvURL, 'http')
                    csvURL = ['https://services.healthtech.dtu.dk' csvURL];
                end
                fprintf('    Found CSV URL (Pattern 1): %s\n', csvURL);
            end
            
            % Pattern 2: Look for CSV link in <a> tags with href
            if isempty(csvURL)
                hrefPattern = ['href=["'']?([^"'']*DeepLocPro-1\.0/tmp/' jobId '/results_[^"'']*\.csv[^"'']*)["'']?'];
                hrefMatches = regexp(pollHtml, hrefPattern, 'tokens', 'once', 'ignorecase');
                if ~isempty(hrefMatches)
                    csvURL = hrefMatches{1};
                    % Make absolute URL if relative
                    if ~startsWith(csvURL, 'http')
                        if startsWith(csvURL, '/')
                            csvURL = ['https://services.healthtech.dtu.dk' csvURL];
                        else
                            csvURL = [baseURL '/' csvURL];
                        end
                    end
                    fprintf('    Found CSV URL (Pattern 2): %s\n', csvURL);
                end
            end
            
            % Pattern 3: Look for any results_*.csv in the tmp directory
            if isempty(csvURL)
                resultsPattern = ['/services/DeepLocPro-1\.0/tmp/' jobId '/results_[^"\s''<>]+\.csv'];
                resultsMatches = regexp(pollHtml, resultsPattern, 'match', 'once');
                if ~isempty(resultsMatches)
                    csvURL = resultsMatches;
                    % Make absolute URL if relative
                    if ~startsWith(csvURL, 'http')
                        csvURL = ['https://services.healthtech.dtu.dk' csvURL];
                    end
                    fprintf('    Found CSV URL (Pattern 3): %s\n', csvURL);
                end
            end
            
            if ~isempty(csvURL)
                if verbose
                    fprintf('    Detected job completion: Found "%s"\n', completionIndicator);
                    fprintf('    Job completed! CSV URL: %s\n', csvURL);
                end
                break;
            else
                if verbose
                    fprintf('    Detected job completion: Found "%s" but could not extract CSV URL from HTML\n', completionIndicator);
                end
            end
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

%% Step 8: Download CSV File
% This section downloads and saves the CSV file

if verbose
    fprintf('  Step 4: Downloading CSV file: %s\n', csvURL);
end

% Use webread to download CSV
csvContent = webread(csvURL, weboptions('Timeout', timeout));

% webread may automatically parse CSV files into tables
% We need to handle this and convert back to text if needed
if istable(csvContent)
    % If webread parsed it as a table, write to temp file and read back as text
    tempFile = [tempname '.csv'];
    writetable(csvContent, tempFile);
    csvContent = fileread(tempFile);
    delete(tempFile);
end

% webread may return as char or string, ensure it's char
if isstring(csvContent)
    csvContent = char(csvContent);
end

if verbose
    fprintf('    CSV file downloaded (%d characters)\n', length(csvContent));
end

%% Step 9: Save CSV File
% This section saves the CSV to disk

% Generate output filename
[~, fastaName, ~] = fileparts(fastaFilePath);
timestamp = datestr(now, 'yyyymmdd_HHMMSS');
csvFilename = sprintf('deeplocpro_%s_%s.csv', fastaName, timestamp);
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

% Display first 500 characters of CSV file
fprintf('\nFirst 500 characters of CSV file:\n');
fprintf('%s\n', csvContent(1:min(500, length(csvContent))));

