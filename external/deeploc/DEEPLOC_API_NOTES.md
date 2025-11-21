- Record:
    - Webserver URL
    https://services.healthtech.dtu.dk/services/DeepLoc-2.1/
    - Submission method (upload/paste)
    Both upload and paste possible. The webserver provides the following details: "Paste or upload protein sequence(s) as fasta format to predict the subcellular localization and membrane association. A maximum of 500 sequences is allowed. The prediction can take a few seconds per sequence depending on the model selected. Protein sequences should not be shorter than 10 amino acids. Sequences beyond the limit of the language model will be truncated by removing the middle part of the sequence. In Slow mode, the limit is 4000 so longer sequences than that will be represented by the concatenation of first and last 2000 amino acids. For the Fast model the limit is 1022. Furthermore, it is recommended to use the "short output (no figures)" option for high-throughput analysis (i.e. when submitting more than 100 sequences in one batch). The maximal active execution time of a job in the queue is 4 hours - if a job happens to fail, please submit a smaller job next time."
    - Form field names
    In the webserver, two choices must be made. The first is "Model" with two check-boxes for either "High-quality (Slow)" or "High-throughput (Fast)". The second is "Output format:" for either "Long output" or "Short output (no figures)".
    - Response handling (immediate/async)
    After pressing submit, a new page opens. Here, one can optionally submit an email address to which a notification is sent. After some time, a few seconds if there are only three sequences, a new page with results opens. This page contains a clickable link "cvs summary", with URL https://services.healthtech.dtu.dk/services/DeepLoc-2.1/tmp/specific_code/results_specific_code.csv, where "specific_code" will be different for each submission.
    - CSV download method
    Click the "cvs summary" button or go to the download url
    - CSV format details
    I have provided the output for a manual run under ./temp/results_691DBF0B002800DBB556BE86.csv. I have also there included the input fasta file ./temp/seqs_added_short.faa
    
    CSV Format Verification:
    - Header: Protein_ID,Localizations,Signals,Membrane types,Cytoplasm,Nucleus,Extracellular,...
    - Data: cluster_8975,Cytoplasm,Peroxisomal targeting signal,Soluble,0.428...,0.354...,...
    - Format matches parseScores.m expectations:
      * Column 1: Protein_ID (gene name) ✓
      * Columns 2-4: Localizations, Signals, Membrane types (ignored by parseScores) ✓
      * Columns 5+: Compartment scores (Cytoplasm, Nucleus, etc.) ✓
    - Test: GSS = parseScores('temp/results_691DBF0B002800DBB556BE86.csv', 'deeploc') should work
    
    Documented (from HTML source analysis):

    - Form action URL and method
      Full URL: https://services.healthtech.dtu.dk/services/DeepLoc-2.1/cgi-bin/webface2.cgi
      Method: POST
      Encoding: multipart/form-data
      Form tag: <form enctype="multipart/form-data" name="agForm" role="form" class="form-horizontal" action="/cgi-bin/webface2.cgi" method="post">

    - Form field names (from deeploc_submit.htm):
      
      Hidden field:
      - name="configfile" value="/var/www/services/services/DeepLoc-2.1/webface.cf"
      
      File upload (option 1):
      - name="uploadfile" type="file"
      - Used when uploading a file from disk
      
      Textarea (option 2):
      - name="fasta" (textarea for pasting sequences)
      - Used when pasting sequences directly
      
      Model selection:
      - name="encode" type="radio"
      - Values: "Slow" (High-quality) or "Fast" (High-throughput)
      - Default: "Slow" (checked)
      
      Output format:
      - name="format" type="radio"
      - Values: "long" (Long output) or "short" (Short output, no figures)
      - Default: "long" (checked)
      
      Submit button:
      - type="submit" value="Submit"

    - POST Request Structure:
      Content-Type: multipart/form-data
      Fields:
        configfile: /var/www/services/services/DeepLoc-2.1/webface.cf
        uploadfile: [FASTA file content] OR fasta: [FASTA string]
        encode: "Slow" or "Fast"
        format: "long" or "short"

    - Response HTML structure (from deeploc_result.htm):
      - Results page uses AngularJS (ng-controller="ResultsCtrl")
      - CSV download link: <a ng-href="{{ JSON.csv_file }}" download>CSV Summary</a>
      - The CSV URL is stored in JSON.csv_file variable (AngularJS binding)
      - Need to extract JSON data from the page to get csv_file value
      
    - CSV link extraction pattern:
      The CSV URL is in an AngularJS variable JSON.csv_file
      Options for extraction:
      1. Search for JSON data in <script> tags on the results page
      2. Look for API endpoint that returns JSON (check network requests)
      3. Use regex to find the actual CSV URL in the rendered HTML after Angular processes it
      4. Pattern might be: /services/DeepLoc-2.1/tmp/[CODE]/results_[CODE].csv
      
      Note: The results page shows the CSV link is dynamically generated via AngularJS.
      The actual CSV URL format from manual testing: 
      https://services.healthtech.dtu.dk/services/DeepLoc-2.1/tmp/specific_code/results_specific_code.csv
      
    - Response flow:
      1. Submit POST request to /cgi-bin/webface2.cgi
      2. Server processes job (async)
      3. Redirects to results page (URL pattern TBD - need to check response)
      4. Results page loads JSON data (source TBD - script tag or API call)
      5. AngularJS renders page with CSV link from JSON.csv_file
      6. CSV can be downloaded from the extracted URL
      
    - TODO for Implementation:
      Need to determine:
      1. What is the redirect URL after POST submission? (check Location header or response)
      2. Where does JSON data come from on results page?
         - Check for <script> tags with JSON data
         - Check for API endpoints (e.g., /cgi-bin/webface2.cgi?jobid=...)
         - Check network requests in browser dev tools
      3. How to extract JSON.csv_file value?
         - If in script tag: parse JavaScript/JSON
         - If via API: make separate request
         - If rendered: use regex on final HTML (after Angular processing)
      
    - Implementation Strategy:
      Since AngularJS processes the page, options:
      A. Wait for page to fully render, then extract CSV URL from final HTML using regex
      B. Find the JSON source (script tag or API) and parse it directly
      C. Check if there's a direct API endpoint that returns JSON with csv_file
      
      Recommended: Try option A first (simpler), fall back to B/C if needed.