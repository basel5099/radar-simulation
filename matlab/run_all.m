%RUN_ALL Master script: validate the bit-true model, then run the
%   end-to-end radar simulation.  Headless-friendly:
%     matlab -batch "cd('matlab'); run_all"
%   Outputs go to generated/matlab_validation and
%   .../matlab_endtoend (gitignored per repo policy).

results = validate_against_golden();
n_pass = sum([results.pass]);
assert(n_pass == numel(results), ...
    'Golden validation failed (%d/%d) â€” fix the model before trusting the sim.', ...
    n_pass, numel(results));

aeris_endtoend_sim();
fprintf('\nrun_all complete: %d/%d golden checks passed, end-to-end sim finished.\n', ...
        n_pass, numel(results));
