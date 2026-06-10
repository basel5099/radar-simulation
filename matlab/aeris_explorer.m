function app = aeris_explorer()
%AERIS_EXPLORER Interactive AERIS-10 radar lab and system explorer.
%
%   A clickable block diagram of the complete radar. Selecting a block
%   shows its specification, the MATLAB model code, the FPGA Verilog
%   source and a live signal view from the bit-true simulation.
%
%   NEW â€” Scenario Lab (bottom left): edit the targets (range / velocity /
%   RCS), noise, AGC gain, MTI, DC notch and CFAR parameters, then press
%   "Apply scenario". Detector-only changes update instantly from the
%   cached Doppler maps; scene changes re-run the full 32-chirp frame
%   through the bit-true pipeline (~15 s, progress shown).
%
%   NEW â€” Guided tour: a plain-language walk through the whole signal
%   chain, block by block (button top right).
%
%   Usage:  aeris_explorer

p = aeris_params();
S = struct();
S.p = p;
S.refs    = aeris.load_chirp_refs(p);
S.rom1024 = aeris.load_twiddle_rom(p.twiddle_1024_file);
S.rom16   = aeris.load_twiddle_rom(p.twiddle_16_file);

% Create the (visible) app window first so the progress dialog has a host.
S.fig = uifigure('Name', 'AERIS-10 Radar Lab & System Explorer', ...
                 'Position', [30 50 1500 860], ...
                 'DeleteFcn', @(~,~) close_tour());
dlg = [];
try %#ok<TRYNC>
    if ~batchStartupOptionUsed
        dlg = uiprogressdlg(S.fig, 'Title', 'AERIS-10 Explorer', ...
            'Message', 'Computing stage-by-stage signals (one chirp)...', ...
            'Indeterminate', 'on');
        drawnow;
    end
end
S.taps = compute_taps(p, S.refs, S.rom1024);
S.maps = load_maps(p);
if ~isempty(dlg), close(dlg); end

% ---------------------------------------------------------------------
% Layout
% ---------------------------------------------------------------------
g = uigridlayout(S.fig, [2 2]);
g.RowHeight   = {44, '1x'};
g.ColumnWidth = {'1.25x', '1x'};

% header
hdr = uigridlayout(g, [1 3]);
hdr.Layout.Row = 1; hdr.Layout.Column = [1 2];
hdr.ColumnWidth = {'1x', 150, 170};
hdr.Padding = [10 4 10 4];
lab = uilabel(hdr, 'Text', ...
    'AERIS-10 Radar Lab â€” click a block to inspect it; edit the scenario below and press Apply', ...
    'FontSize', 15, 'FontWeight', 'bold');
lab.Layout.Column = 1;
btnTour = uibutton(hdr, 'Text', 'Guided tour', ...
    'ButtonPushedFcn', @(~,~) start_tour());
btnTour.Layout.Column = 2;
btnVal = uibutton(hdr, 'Text', 'Run 25 golden checks', ...
    'ButtonPushedFcn', @(~,~) run_validation());
btnVal.Layout.Column = 3;

% left column: diagram + scenario lab
left = uigridlayout(g, [2 1]);
left.Layout.Row = 2; left.Layout.Column = 1;
left.RowHeight = {'1x', 235};
left.Padding = [0 0 0 0];  left.RowSpacing = 4;

S.ax = uiaxes(left);
disableDefaultInteractivity(S.ax);
S.ax.Toolbar.Visible = 'off';
hold(S.ax, 'on');
axis(S.ax, [0 100 0 66]);
axis(S.ax, 'off');

% --- scenario lab panel ---
labp = uipanel(left, 'Title', 'Scenario Lab â€” targets and processing controls');
lg = uigridlayout(labp, [1 2]);
lg.ColumnWidth = {'1x', 330};
lg.Padding = [6 6 6 6];

S.tbl = uitable(lg, ...
    'Data', {'T1', true,  40,   -8,  -20; ...
             'T2', true, 440,   16,   10; ...
             'T3', true, 900, -21.4,  26; ...
             'C1', true, 250,    0,   12}, ...
    'ColumnName', {'target', 'on', 'range [m]', 'vel [m/s]', 'RCS [dBsm]'}, ...
    'ColumnEditable', [false true true true true], ...
    'ColumnWidth', {52, 36, 78, 78, 86}, ...
    'RowName', []);

ctl = uigridlayout(lg, [6 4]);
ctl.Padding = [0 0 0 0];  ctl.RowSpacing = 3;  ctl.ColumnSpacing = 4;
ctl.ColumnWidth = {86, 70, 86, 70};
    function L = lbl(txt)
        L = uilabel(ctl, 'Text', txt, 'FontSize', 11);
    end
lbl('MTI clutter filt.');
S.ctl.mti = uicheckbox(ctl, 'Text', '', 'Value', true, ...
    'ValueChangedFcn', @(~,~) refresh_views());
lbl('DC notch width');
S.ctl.notch = uispinner(ctl, 'Limits', [0 3], 'Value', 0, 'RoundFractionalValues', 'on');
lbl('CFAR alpha Q4.4');
S.ctl.alpha = uispinner(ctl, 'Limits', [1 255], 'Value', 8, 'RoundFractionalValues', 'on');
lbl('CFAR guard');
S.ctl.guard = uispinner(ctl, 'Limits', [0 8], 'Value', 2, 'RoundFractionalValues', 'on');
lbl('CFAR train');
S.ctl.train = uispinner(ctl, 'Limits', [1 16], 'Value', 8, 'RoundFractionalValues', 'on');
lbl('AGC gain 2^n');
S.ctl.gain = uispinner(ctl, 'Limits', [-7 7], 'Value', -4, 'RoundFractionalValues', 'on');
lbl('noise sigma LSB');
S.ctl.noise = uieditfield(ctl, 'numeric', 'Limits', [0 30], 'Value', 2.0);
S.ctl.apply = uibutton(ctl, 'Text', 'Apply scenario', 'FontWeight', 'bold', ...
    'BackgroundColor', [0.82 0.90 1.0], 'ButtonPushedFcn', @(~,~) apply_scenario());
S.ctl.apply.Layout.Column = [3 4];
S.ctl.reset = uibutton(ctl, 'Text', 'Reset defaults', ...
    'ButtonPushedFcn', @(~,~) reset_defaults());
S.ctl.reset.Layout.Column = [1 2];
S.ctl.status = uilabel(ctl, 'Text', 'ready', 'FontSize', 11, ...
    'FontColor', [0.25 0.45 0.25]);
S.ctl.status.Layout.Column = [1 4];

% right column: block title + tabs
right = uigridlayout(g, [2 1]);
right.Layout.Row = 2; right.Layout.Column = 2;
right.RowHeight = {32, '1x'};
right.Padding = [0 0 0 0];
S.blockTitle = uilabel(right, 'Text', 'Select a block...', ...
    'FontSize', 15, 'FontWeight', 'bold', 'FontColor', [0.05 0.25 0.55]);
S.tabs = uitabgroup(right);
tabSpec = uitab(S.tabs, 'Title', 'Specification');
tabM    = uitab(S.tabs, 'Title', 'MATLAB model');
tabV    = uitab(S.tabs, 'Title', 'FPGA source (Verilog)');
tabSig  = uitab(S.tabs, 'Title', 'Signal view');

gs = uigridlayout(tabSpec, [1 1]); gs.Padding = [4 4 4 4];
S.txtSpec = uitextarea(gs, 'Editable', 'off', 'FontName', 'Consolas', 'FontSize', 13);

gm = uigridlayout(tabM, [2 1]); gm.RowHeight = {28, '1x'}; gm.Padding = [4 4 4 4];
S.btnEditM = uibutton(gm, 'Text', 'Open in MATLAB Editor', ...
    'ButtonPushedFcn', @(~,~) open_in_editor('m'));
S.txtM = uitextarea(gm, 'Editable', 'off', 'FontName', 'Consolas', 'FontSize', 12);

gv = uigridlayout(tabV, [2 1]); gv.RowHeight = {28, '1x'}; gv.Padding = [4 4 4 4];
S.btnEditV = uibutton(gv, 'Text', 'Open in MATLAB Editor', ...
    'ButtonPushedFcn', @(~,~) open_in_editor('v'));
S.txtV = uitextarea(gv, 'Editable', 'off', 'FontName', 'Consolas', 'FontSize', 12);

gp = uigridlayout(tabSig, [2 1]); gp.RowHeight = {34, '1x'}; gp.Padding = [2 2 2 2];
S.sigCaption = uilabel(gp, 'Text', '', 'FontSize', 12, 'FontAngle', 'italic', ...
    'WordWrap', 'on', 'FontColor', [0.25 0.25 0.25]);
S.axSig = uiaxes(gp);

% ---------------------------------------------------------------------
S.blocks = block_db(p);
S.rects = gobjects(1, numel(S.blocks));
S.curId = '';
S.tourFig = [];
S.tourStep = 0;
S.lastScn = [];
if ~isempty(S.maps), S.lastScn = read_scenario(); end   % matches saved demo run
draw_diagram();
select_block('mf');

app.fig = S.fig;
app.select = @select_block;
app.blocks = {S.blocks.id};
app.tabs = S.tabs;
app.apply = @apply_scenario;
app.table = S.tbl;
app.controls = S.ctl;
app.tour_start = @start_tour;
app.tour_next = @() tour_go(S.tourStep + 1);
app.tour_close = @close_tour;

% =====================================================================
%  nested functions
% =====================================================================
    function draw_diagram()
        ax = S.ax;
        text(ax, 1, 63.5, 'TRANSMIT', 'FontWeight', 'bold', 'FontSize', 10, 'Color', [0.6 0.35 0.05]);
        text(ax, 1, 47.5, 'RECEIVE / DIGITAL DOWN-CONVERTER (400 \rightarrow 100 MSPS)', ...
            'FontWeight', 'bold', 'FontSize', 10, 'Color', [0.1 0.3 0.6]);
        text(ax, 1, 29.5, 'FPGA SIGNAL PROCESSING (XC7A50T/100T)', ...
            'FontWeight', 'bold', 'FontSize', 10, 'Color', [0.1 0.3 0.6]);
        for k = 1:numel(S.blocks)
            b = S.blocks(k);
            S.rects(k) = patch(ax, ...
                b.x + [0 b.w b.w 0], b.y + [0 0 b.h b.h], b.color, ...
                'EdgeColor', [0.25 0.25 0.25], 'LineWidth', 1.0, ...
                'ButtonDownFcn', @(~,~) select_block(b.id), ...
                'PickableParts', 'all');
            t = text(ax, b.x + b.w/2, b.y + b.h/2, b.label, ...
                'HorizontalAlignment', 'center', 'FontSize', 9.5, ...
                'FontWeight', 'bold');
            t.PickableParts = 'none';
        end
        A = {...
            [10   57; 13   57];      % STM32 -> chirp gen
            [27   57; 30   57];      % chirp gen -> DAC
            [40   57; 43   57];      % DAC -> TX RF
            [59   57; 62   57];      % TX RF -> antenna
            [70   53; 70   45];      % antenna down to RX RF
            [62   41; 59   41];      % RX RF -> ADC
            [47   41; 44   41];      % ADC -> mixer
            [33   41; 30.5 41];      % mixer -> CIC
            [22   41; 20   41];      % CIC -> FIR
            [11.5 41; 9.5  41];      % FIR -> AGC
            [38.5 35; 38.5 37];      % NCO up into mixer
            [5 37; 5 31.5; 19.5 31.5; 19.5 27];   % AGC down into matched filter
            };
        for k = 1:numel(A), draw_arrow(ax, A{k}); end
        dsp = {'cmem','mf','dec','mti','dop','notch','cfar','usb'};
        for k = 1:numel(dsp)-1
            b1 = get_block(dsp{k});  b2 = get_block(dsp{k+1});
            draw_arrow(ax, [b1.x+b1.w b1.y+b1.h/2; b2.x b2.y+b2.h/2]);
        end
        leg = {[0.80 0.92 0.80], 'control',        2; ...
               [1.00 0.88 0.72], 'transmit',      13; ...
               [0.92 0.92 0.92], 'analog RF',     25; ...
               [0.97 0.85 0.85], 'data converter',38; ...
               [0.80 0.88 0.98], 'FPGA DSP (bit-true, 25/25 validated)', 55; ...
               [0.93 0.87 0.99], 'memory',        86; ...
               [1.00 0.97 0.75], 'output',        95};
        for k = 1:size(leg, 1)
            xx = leg{k,3};
            patch(ax, xx + [0 2 2 0], 2 + [0 0 2 2], leg{k,1}, ...
                  'EdgeColor', [0.3 0.3 0.3], 'PickableParts', 'none');
            text(ax, xx + 2.6, 3, leg{k,2}, 'FontSize', 8, 'PickableParts', 'none');
        end
    end

    function b = get_block(id)
        b = S.blocks(strcmp({S.blocks.id}, id));
    end

    function select_block(id)
        b = get_block(id);
        k = find(strcmp({S.blocks.id}, id));
        S.curId = id;
        set(S.rects, 'LineWidth', 1.0, 'EdgeColor', [0.25 0.25 0.25]);
        set(S.rects(k), 'LineWidth', 3.0, 'EdgeColor', [0.85 0.10 0.10]);
        S.blockTitle.Text = ['  ' char(string(b.spec{1}))];
        S.txtSpec.Value = b.spec;
        S.curM = b.mfile;  S.curV = b.vfile;
        S.txtM.Value = read_src(b.mfile, ...
            'No dedicated MATLAB file for this block â€” see aeris_endtoend_sim.m / aeris_params.m.');
        S.txtV.Value = read_src(b.vfile, ...
            'No FPGA source â€” this part is analog hardware / firmware (see datasheets in 7_Components... and 9_Firmware).');
        S.btnEditM.Enable = matlab.lang.OnOffSwitchState(~isempty(b.mfile) && isfile(b.mfile));
        S.btnEditV.Enable = matlab.lang.OnOffSwitchState(~isempty(b.vfile) && isfile(b.vfile));
        S.sigCaption.Text = caption_text(id);
        plot_block(S.axSig, id, S.taps, S.maps, S.p, ui_state());
        drawnow limitrate;
    end

    function u = ui_state()
        u = struct('use_mti', logical(S.ctl.mti.Value), ...
                   'notch_width', S.ctl.notch.Value);
    end

    function refresh_views()
        if ~isempty(S.curId), select_block(S.curId); end
    end

    function open_in_editor(which)
        if which == 'm', f = S.curM; else, f = S.curV; end
        if ~isempty(f) && isfile(f), edit(f); end
    end

% ----------------------- scenario lab --------------------------------
    function scn = read_scenario()
        D = S.tbl.Data;
        scn.table = D;
        scn.noise_std = S.ctl.noise.Value;
        scn.gc_shift  = S.ctl.gain.Value;
        phases = [20 0 135 60];
        tg = struct('range_m', {}, 'velocity_mps', {}, 'rcs_dbsm', {}, 'phase_deg', {});
        for r = 1:size(D, 1)
            if D{r, 2}
                tg(end+1) = struct('range_m', D{r,3}, 'velocity_mps', D{r,4}, ...
                    'rcs_dbsm', D{r,5}, 'phase_deg', phases(min(r, numel(phases)))); %#ok<AGROW>
            end
        end
        scn.targets = tg;
        scn.clutter = struct([]);
    end

    function apply_scenario()
        scn = read_scenario();
        frame_changed = isempty(S.maps) || isempty(S.lastScn) || ...
            ~isequal(scn.table, S.lastScn.table) || ...
            scn.noise_std ~= S.lastScn.noise_std || ...
            scn.gc_shift  ~= S.lastScn.gc_shift;
        if frame_changed
            if isempty(scn.targets)
                uialert(S.fig, 'Enable at least one target.', 'Scenario');
                return;
            end
            t0 = tic;
            d2 = [];
            try %#ok<TRYNC>
                if ~batchStartupOptionUsed
                    d2 = uiprogressdlg(S.fig, 'Title', 'AERIS-10', ...
                        'Message', 'Running 32-chirp frame through the bit-true pipeline...');
                end
            end
            cb = @(frac, msg) progress_update(d2, frac, msg);
            R = aeris.run_frame(scn, S.p, S.refs, S.rom1024, S.rom16, cb);
            if ~isempty(d2), close(d2); end
            S.maps = R;
            detector_pass();
            S.lastScn = scn;
            ndet = numel(pick(S.maps, 'det_mti', 'det', S.ctl.mti.Value));
            S.ctl.status.Text = sprintf('frame run %.1f s â€” %d detection cluster(s)', ...
                toc(t0), ndet);
        else
            detector_pass();
            S.lastScn = scn;
            ndet = numel(pick(S.maps, 'det_mti', 'det', S.ctl.mti.Value));
            S.ctl.status.Text = sprintf('detector updated instantly â€” %d detection cluster(s)', ndet);
        end
        refresh_views();
    end

    function detector_pass()
        if isempty(S.maps), return; end
        w = S.ctl.notch.Value;
        a = S.ctl.alpha.Value;
        gg = S.ctl.guard.Value;
        tt = S.ctl.train.Value;
        [ni, nq] = aeris.dc_notch(S.maps.map_i, S.maps.map_q, w);
        [S.maps.flags, S.maps.mags, S.maps.thrs] = aeris.cfar_ca(ni, nq, gg, tt, a, 'CA');
        [ni2, nq2] = aeris.dc_notch(S.maps.mmap_i, S.maps.mmap_q, w);
        [S.maps.mflags, S.maps.mmags, S.maps.mthrs] = aeris.cfar_ca(ni2, nq2, gg, tt, a, 'CA');
        S.maps.det     = aeris.cluster_detections(S.maps.flags,  S.maps.mags,  S.p, ...
                            S.maps.cal_offset, S.maps.chirp_sign);
        S.maps.det_mti = aeris.cluster_detections(S.maps.mflags, S.maps.mmags, S.p, ...
                            S.maps.cal_offset, S.maps.chirp_sign);
    end

    function reset_defaults()
        S.tbl.Data = {'T1', true,  40,   -8,  -20; ...
                      'T2', true, 440,   16,   10; ...
                      'T3', true, 900, -21.4,  26; ...
                      'C1', true, 250,    0,   12};
        S.ctl.mti.Value = true;   S.ctl.notch.Value = 0;
        S.ctl.alpha.Value = 8;    S.ctl.guard.Value = 2;
        S.ctl.train.Value = 8;    S.ctl.gain.Value = -4;
        S.ctl.noise.Value = 2.0;
        S.ctl.status.Text = 'defaults restored â€” press Apply scenario';
    end

    function run_validation()
        d2 = [];
        try %#ok<TRYNC>
            if ~batchStartupOptionUsed
                d2 = uiprogressdlg(S.fig, 'Title', 'AERIS-10', 'Indeterminate', 'on', ...
                    'Message', 'Validating the MATLAB model against the FPGA golden vectors...');
            end
        end
        try
            r = validate_against_golden();
            if ~isempty(d2), close(d2); end
            uialert(S.fig, sprintf('%d/%d checks passed (bit-exact).', ...
                sum([r.pass]), numel(r)), 'Golden validation', 'Icon', 'success');
        catch err
            if ~isempty(d2), close(d2); end
            uialert(S.fig, err.message, 'Validation failed');
        end
    end

% ----------------------- guided tour ---------------------------------
    function start_tour()
        if ~isempty(S.tourFig) && isvalid(S.tourFig)
            figure(S.tourFig);
            return;
        end
        S.tourFig = uifigure('Name', 'AERIS-10 Guided Tour', ...
            'Position', [60 80 520 300]);
        tg = uigridlayout(S.tourFig, [2 3]);
        tg.RowHeight = {'1x', 34};
        tg.ColumnWidth = {'1x', '1x', '1x'};
        S.tourText = uitextarea(tg, 'Editable', 'off', 'FontSize', 13, ...
            'FontName', 'Segoe UI');
        S.tourText.Layout.Row = 1;  S.tourText.Layout.Column = [1 3];
        b1 = uibutton(tg, 'Text', '< Previous', 'ButtonPushedFcn', @(~,~) tour_go(S.tourStep - 1));
        b1.Layout.Row = 2; b1.Layout.Column = 1;
        b2 = uibutton(tg, 'Text', 'Next >', 'FontWeight', 'bold', ...
            'ButtonPushedFcn', @(~,~) tour_go(S.tourStep + 1));
        b2.Layout.Row = 2; b2.Layout.Column = 2;
        b3 = uibutton(tg, 'Text', 'Close tour', 'ButtonPushedFcn', @(~,~) close_tour());
        b3.Layout.Row = 2; b3.Layout.Column = 3;
        tour_go(1);
    end

    function tour_go(k)
        steps = tour_steps();
        k = max(1, min(k, numel(steps)));
        S.tourStep = k;
        st = steps(k);
        select_block(st.id);
        S.tabs.SelectedTab = S.tabs.Children(4);    % show the signal view
        if ~isempty(S.tourFig) && isvalid(S.tourFig)
            S.tourText.Value = [{sprintf('Step %d of %d â€” %s', k, numel(steps), st.title)}; ...
                                {''}; splitlines(string(st.text))];
        end
    end

    function close_tour()
        if ~isempty(S.tourFig) && isvalid(S.tourFig)
            delete(S.tourFig);
        end
        S.tourFig = [];
    end
end

% =====================================================================
%  helpers
% =====================================================================
function progress_update(d, frac, msg)
if ~isempty(d) && isvalid(d)
    d.Value = frac;
    d.Message = sprintf('Bit-true pipeline: %s', msg);
end
end

function v = pick(s, fa, fb, cond)
if cond, v = s.(fa); else, v = s.(fb); end
end

function txt = read_src(f, fallback)
if ~isempty(f) && isfile(f)
    txt = splitlines(string(fileread(f)));
else
    txt = {fallback};
end
end

function draw_arrow(ax, pts)
plot(ax, pts(:,1), pts(:,2), 'k-', 'LineWidth', 1.1, 'PickableParts', 'none');
d = pts(end,:) - pts(end-1,:);  d = d / max(norm(d), eps);
n = [-d(2) d(1)];
tip = pts(end,:); b1 = tip - 1.6*d + 0.8*n; b2 = tip - 1.6*d - 0.8*n;
patch(ax, [tip(1) b1(1) b2(1)], [tip(2) b1(2) b2(2)], [0 0 0], ...
      'EdgeColor', 'none', 'PickableParts', 'none');
end

function taps = compute_taps(p, refs, rom1024)
% One long chirp of the default scene through the bit-true chain.
LEAD = 512;  NBB = 3072;
nadc = LEAD + 4*(NBB + 64);
targets = struct( ...
    'range_m',      {40,   440,   900}, ...
    'velocity_mps', {-8,   16,  -21.4}, ...
    'rcs_dbsm',     {-20,  10,    26}, ...
    'phase_deg',    {20,    0,   135});
clutter = struct('range_m', 250, 'velocity_mps', 0, 'rcs_dbsm', 12, 'phase_deg', 60);
rng(42, 'twister');
adc = aeris.scene_generate_adc(targets, nadc, p, chirp="long", ...
    noise_std=2.0, chirp_sign=-1, clutter=clutter, tx_start_samp=LEAD);
d = aeris.ddc_chain(adc, p);
i0 = LEAD/4;
gc_i = aeris.rx_gain_control(d.bb_i(i0+1:i0+NBB), -4);
gc_q = aeris.rx_gain_control(d.bb_q(i0+1:i0+NBB), -4);
mfres = aeris.mf_multi_segment(gc_i, gc_q, refs, true, rom1024, framing="rtl");
[dec_i, dec_q] = aeris.range_bin_decimator(mfres.seg_re(1,:), mfres.seg_im(1,:), 1, 0);

taps = struct();
taps.targets = targets;  taps.clutter = clutter;
taps.adc = adc;  taps.lead = LEAD;
taps.sin = d.sin;  taps.cos = d.cos;
taps.mix_i = d.mix_i;  taps.mix_q = d.mix_q;
taps.cic_i = d.cic_i;  taps.cic_q = d.cic_q;
taps.fir_i = d.fir_i;  taps.fir_q = d.fir_q;
taps.bb_i = d.bb_i;    taps.bb_q = d.bb_q;
taps.gc_i = gc_i;      taps.gc_q = gc_q;
taps.refs = refs;
taps.mf = mfres;
taps.dec_i = dec_i;    taps.dec_q = dec_q;
taps.dac_lut = aeris.read_mem_hex(fullfile(p.fpga_dir, 'long_chirp_lut.mem'), 8, false);
end

function maps = load_maps(p)
f = fullfile(p.gen_dir, 'matlab_endtoend', 'endtoend_results.mat');
if isfile(f)
    maps = load(f);
    % normalise field names used by the lab (saved demo uses same ones)
    if ~isfield(maps, 'mmags'), maps.mmags = maps.mags; end
    if ~isfield(maps, 'mthrs'), maps.mthrs = maps.thrs; end
else
    maps = [];
end
end

% ---------------------------------------------------------------------
function plot_block(ax, id, taps, maps, p, ui)
cla(ax, 'reset');
hold(ax, 'on');  grid(ax, 'on');
switch id
    case 'stm32'
        no_signal(ax, ['Supervisor only - not in the signal path.' newline ...
            'Configures the FPGA via USB opcodes 0x01..0x2C' newline ...
            '(chirp timing, CFAR, MTI, AGC, gain).']);
    case 'chirp'
        plot(ax, taps.dac_lut(1:600), '-');
        xlabel(ax, 'sample @ 120 MHz'); ylabel(ax, 'DAC code (8-bit)');
        title(ax, 'long\_chirp\_lut.mem - first 600 of 3600 samples (30 \mus, 20 MHz sweep)');
    case 'dac'
        plot(ax, taps.dac_lut(1:200), '.-');
        xlabel(ax, 'sample @ 120 MHz'); ylabel(ax, 'code (offset binary, mid = 128)');
        title(ax, 'AD9708 drive waveform (chirp start)');
    case {'txrf', 'ant', 'rxrf'}
        n = 2^13;
        w = 0.5 - 0.5*cos(2*pi*(0:n-1)/(n-1));
        spec = 20*log10(abs(fft((taps.adc(1:n)-128).*w, n)) + 1);
        fax = (0:n-1)/n*p.fs_adc/1e6;
        plot(ax, fax(1:n/2), spec(1:n/2));
        xlim(ax, [0 200]);
        xlabel(ax, 'frequency [MHz]'); ylabel(ax, '|X| [dB]');
        title(ax, 'Received signal at IF (echoes around 120 MHz, chirp \pm10 MHz)');
    case 'adc'
        plot(ax, (0:2999)/p.fs_adc*1e6, taps.adc(1:3000));
        xlabel(ax, 'time [\mus]'); ylabel(ax, 'ADC code');
        title(ax, 'AD9484 output - 8-bit unsigned @ 400 MSPS');
    case 'nco'
        plot(ax, taps.sin(1:120), '.-'); plot(ax, taps.cos(1:120), '.-');
        legend(ax, 'sin', 'cos');
        xlabel(ax, 'sample @ 400 MHz'); ylabel(ax, 'amplitude (16-bit)');
        title(ax, 'NCO 120 MHz (note quadrant-2/3 sin/cos swap - as-built RTL)');
    case 'mix'
        plot(ax, taps.mix_i(1:2000)); plot(ax, taps.mix_q(1:2000));
        legend(ax, 'I', 'Q');
        xlabel(ax, 'sample @ 400 MHz'); ylabel(ax, '18-bit');
        title(ax, 'Mixer output (sum + difference products)');
    case 'cic'
        plot(ax, taps.cic_i(1:1500)); plot(ax, taps.cic_q(1:1500));
        legend(ax, 'I', 'Q');
        xlabel(ax, 'sample @ 100 MHz'); ylabel(ax, '18-bit');
        title(ax, 'CIC \div4 output - image products removed');
    case 'fir'
        h = 20*log10(abs(fft(p.fir_coeffs/2^17, 1024)) + 1e-6);
        plot(ax, (0:511)/1024*p.fs_sys/1e6, h(1:512), 'LineWidth', 1.2);
        xlabel(ax, 'frequency [MHz]'); ylabel(ax, '|H| [dB]');
        title(ax, '32-tap FIR response (passband \approx chirp \pm10 MHz)');
    case 'agc'
        plot(ax, taps.bb_i(1:1500)); plot(ax, taps.gc_i(1:1500));
        legend(ax, 'before gain', 'after gain');
        xlabel(ax, 'sample @ 100 MHz'); ylabel(ax, '16-bit I');
        title(ax, 'Digital gain stage - keeps the unscaled FFT linear');
    case 'cmem'
        plot(ax, taps.refs.long_i(1, 1:300)); plot(ax, taps.refs.long_q(1, 1:300));
        legend(ax, 'I', 'Q');
        xlabel(ax, 'sample @ 100 MHz'); ylabel(ax, 'Q15');
        title(ax, 'Matched-filter reference chirp (segment 0 of 4, from .mem)');
    case 'mf'
        prof = abs(taps.mf.seg_re(1,:)) + abs(taps.mf.seg_im(1,:));
        semilogy(ax, ((0:1023) - 20)*p.range_per_bin, prof + 1, 'LineWidth', 1.0);
        for t = taps.targets, xline(ax, t.range_m, 'r--'); end
        xline(ax, taps.clutter.range_m, 'm--');
        xlim(ax, [-50 1550]);
        xlabel(ax, 'range [m]'); ylabel(ax, '|I|+|Q|');
        title(ax, 'Pulse compression output, segment 0 (red = targets, magenta = clutter)');
    case 'dec'
        stem(ax, ((0:63)*16 + 8 - 20)*p.range_per_bin, ...
             abs(taps.dec_i) + abs(taps.dec_q), 'filled');
        xlabel(ax, 'range [m]'); ylabel(ax, '|I|+|Q|');
        title(ax, 'Range-bin decimator: 1024 \rightarrow 64 bins (peak mode, 24 m/bin)');
    case 'mti'
        if isempty(maps), need_sim(ax); return; end
        plot(ax, maps.range_axis_dec, abs(maps.frame_dec_i(2,:)) + abs(maps.frame_dec_q(2,:)), '.-');
        mi = aeris.sat_int(maps.frame_dec_i(2,:) - maps.frame_dec_i(1,:), 16);
        mq = aeris.sat_int(maps.frame_dec_q(2,:) - maps.frame_dec_q(1,:), 16);
        plot(ax, maps.range_axis_dec, abs(mi) + abs(mq), '.-');
        legend(ax, 'chirp 1 (raw)', 'after 2-pulse MTI');
        xlabel(ax, 'range [m]'); ylabel(ax, '|I|+|Q|');
        title(ax, 'MTI: stationary returns cancelled');
    case 'dop'
        if isempty(maps), need_sim(ax); return; end
        [mi, mq, tag] = select_path(maps, ui, false);
        show_map(ax, maps, mi, mq, ['Range-Doppler map (sub-frame 0, ' tag ')']);
    case 'notch'
        if isempty(maps), need_sim(ax); return; end
        [mi, mq, tag] = select_path(maps, ui, true);
        ttl = sprintf('DC notch width %d (%s)', ui.notch_width, tag);
        if ui.notch_width == 0, ttl = [ttl ' - width 0 = pass-through']; end
        show_map(ax, maps, mi, mq, ttl);
    case 'cfar'
        if isempty(maps), need_sim(ax); return; end
        [mi, mq, tag] = select_path(maps, ui, true);
        show_map(ax, maps, mi, mq, ['CFAR detections (white squares, ' tag ')']);
        if ui.use_mti, fl = maps.mflags; else, fl = maps.flags; end
        [rr, dd] = find(fl(:, 1:16));
        plot(ax, maps.vel_axis(dd), maps.range_axis_dec(rr), 'ws', ...
             'MarkerSize', 11, 'LineWidth', 1.5);
    case 'usb'
        if isempty(maps), need_sim(ax); return; end
        axis(ax, 'off');
        if ui.use_mti, dets = maps.det_mti; tag = 'MTI on'; else, dets = maps.det; tag = 'MTI off'; end
        txt = {sprintf('CFAR detection clusters (%s), as streamed to the GUI:', tag), ''};
        for k = 1:numel(dets)
            txt{end+1} = sprintf('  R = %6.1f m   v = %+6.1f m/s   sub-frame %d   mag %6.0f', ...
                dets(k).range_m, dets(k).vel_mps, dets(k).subframe, dets(k).mag); %#ok<AGROW>
        end
        if isempty(dets), txt{end+1} = '  (no detections with the current settings)'; end
        text(ax, 0.02, 0.95, txt, 'FontName', 'Consolas', 'FontSize', 12, ...
             'VerticalAlignment', 'top', 'Interpreter', 'none');
    otherwise
        no_signal(ax, 'No signal view for this block.');
end
end

function [mi, mq, tag] = select_path(maps, ui, apply_notch)
if ui.use_mti
    mi = maps.mmap_i;  mq = maps.mmap_q;  tag = 'MTI on';
else
    mi = maps.map_i;   mq = maps.map_q;   tag = 'MTI off';
end
if apply_notch && ui.notch_width > 0
    [mi, mq] = aeris.dc_notch(mi, mq, ui.notch_width);
end
end

function show_map(ax, maps, mi, mq, ttl)
mag_db = 20*log10(abs(mi(:,1:16)) + abs(mq(:,1:16)) + 1);
[v, order] = sort(maps.vel_axis);
imagesc(ax, v, maps.range_axis_dec, mag_db(:, order));
axis(ax, 'xy');  colormap(ax, 'jet');  colorbar(ax);
xlabel(ax, 'velocity [m/s]'); ylabel(ax, 'range [m]');
ylim(ax, [0 1550]);
title(ax, ttl);
end

function need_sim(ax)
no_signal(ax, ['Frame-level view - press  "Apply scenario"  (bottom left)' newline ...
    'to run the 32-chirp frame through the bit-true pipeline first.']);
end

function no_signal(ax, msg)
axis(ax, 'off');
text(ax, 0.5, 0.5, msg, 'HorizontalAlignment', 'center', 'FontSize', 13, ...
     'Color', [0.35 0.35 0.35]);
end

% ---------------------------------------------------------------------
function c = caption_text(id)
switch id
    case 'stm32', c = 'The housekeeper: it boots the radar, steers the beam and sets every processing knob â€” but never touches a sample.';
    case 'chirp', c = 'A radar does not shout a bang â€” it sings a sweep. Spreading the pulse over 20 MHz is what later buys 7.5 m range resolution without megawatt power.';
    case 'dac',   c = 'The chirp leaves the digital world here: 8-bit codes at 120 MHz become an analog waveform ready for up-conversion to 10.5 GHz.';
    case 'txrf',  c = 'Up-conversion, filtering, per-element phase shifting and power amplification: 16 channels form and steer the transmit beam electronically.';
    case 'ant',   c = 'The array. More elements = narrower beam = more gain. Phase offsets across elements steer the beam without any moving part.';
    case 'rxrf',  c = 'The faint echo (down by ~1/R^4!) is amplified, beamformed and mixed down to a 120 MHz intermediate frequency the ADC can digest.';
    case 'adc',   c = 'Everything the digital radar will ever know: 8-bit numbers, 400 million per second. Watch the chirp burst at the start, then echoes buried in noise.';
    case 'nco',   c = 'A digital local oscillator: a phase counter plus a quarter-wave sine table. Multiplying by it shifts the 120 MHz IF down to 0 Hz.';
    case 'mix',   c = 'The multiply: signal x sin/cos creates a copy at 0 Hz (wanted) and one at 240 MHz (unwanted â€” the filters kill it next).';
    case 'cic',   c = 'Filter and throw away 3 of every 4 samples: 400 -> 100 MSPS. CIC filters need no multipliers â€” perfect for FPGAs.';
    case 'fir',   c = 'The precision filter: flattens the passband around the chirp and removes what the CIC let through, then rounds 18 -> 16 bits.';
    case 'agc',   c = 'Fixed-point reality: the FFTs ahead have no internal scaling, so the gain must be backed off before strong scenes clip them. Try gain 0 in the lab and watch detections die.';
    case 'cmem',  c = 'The matched filter needs to know exactly what was transmitted â€” these Q15 samples are the same .mem files the FPGA build uses.';
    case 'mf',    c = 'Pulse compression â€” the heart of the radar. Correlating the echo with the known chirp concentrates its spread-out energy into a sharp peak at the target range.';
    case 'dec',   c = '1024 fine range bins are too many to Doppler-process; keep the peak of every 16 (24 m cells, 1.5 km coverage).';
    case 'mti',   c = 'Subtract the previous pulse: anything that did not move cancels. Buildings vanish, drones survive. Toggle MTI in the lab to see it.';
    case 'dop',   c = 'A second FFT across the 16 pulses sorts each range cell by velocity â€” this is how a radar tells a hovering bird from a passing car.';
    case 'notch', c = 'Zeroing the bins around 0 m/s removes residual stationary leakage (including the ADC half-LSB DC artifact).';
    case 'cfar',  c = 'No fixed threshold survives real noise. CFAR compares each cell against its neighbours so the false-alarm rate stays constant. Tune alpha in the lab!';
    case 'usb',   c = 'The end product: a short list of (range, velocity, magnitude) detections streamed to the PC map display.';
    otherwise,    c = '';
end
end

function steps = tour_steps()
T = {
'chirp', 'The transmitted waveform', ['A pulse radar measures distance by timing echoes. Instead of one powerful spike, AERIS-10 transmits a 30 microsecond "chirp" that sweeps 20 MHz. The energy of a long pulse with the resolution of a short one - that trick is called pulse compression, and you will see it completed at the matched filter.'];
'dac',   'Into the analog world', ['The chirp is stored as 3600 8-bit samples and played out by the DAC at 120 MHz. From here on it is an analog signal: filtered, mixed up to 10.5 GHz, amplified and radiated.'];
'ant',   'The phased array', ['16 antenna channels transmit the same chirp with programmable phase offsets. The wavefronts add up in one chosen direction - electronic beam steering with no moving parts (azimuth is rotated mechanically).'];
'rxrf',  'The echo comes home', ['A target scatters a tiny fraction of the energy back. Echo power falls with the FOURTH power of distance. The receive chain amplifies it and mixes it down to a 120 MHz intermediate frequency.'];
'adc',   'Digitization', ['The ADC samples the IF signal: 8-bit values, 400 million per second. Everything after this point - everything - is arithmetic. That is why this whole radar can be learned in MATLAB.'];
'nco',   'A digital oscillator', ['To move the signal from 120 MHz to 0 Hz, the FPGA generates its own sine and cosine: a 32-bit phase counter addressing a 64-entry quarter-wave table. (Look closely: this RTL has a quadrant bug we found with this very simulation.)'];
'mix',   'Down-conversion', ['Multiplying the ADC stream by sin and cos produces the complex baseband signal (I and Q). A copy also appears at 240 MHz - the filters next door remove it.'];
'cic',   'Decimation', ['A 5-stage CIC filter averages and keeps every 4th sample: 400 to 100 MSPS. CIC filters use only adders, which is why FPGAs love them.'];
'fir',   'Precision filtering', ['A 32-tap FIR flattens the band the chirp occupies and cleans up the CIC. Note the fixed-point details everywhere: 18-bit data, 36-bit accumulators, rounding - this simulation reproduces every bit.'];
'agc',   'The gain dilemma', ['Fixed-point FFTs with no internal scaling clip when the scene is strong, and weak targets die in quantization when it is too weak. The AGC walks that line. Experiment: set gain to 0 in the lab and apply.'];
'mf',    'Pulse compression', ['The star of the show. The echo is correlated with the known chirp (via FFT, multiply by conjugate, inverse FFT). All the energy spread over 30 microseconds collapses into a sharp peak exactly at the target range.'];
'dec',   'Range cells', ['1024 fine bins become 64 cells of 24 m by keeping each group''s peak - enough resolution for detection, few enough for the next FFT.'];
'mti',   'Moving target indication', ['Subtract the previous pulse from the current one: stationary clutter cancels perfectly, movers survive. In the demo scene a strong reflector at 250 m disappears - and a masked drone at 440 m becomes visible.'];
'dop',   'Velocity', ['Across 16 pulses, a moving target''s phase rotates a little every pulse. A 16-point FFT across pulses sorts each range cell by velocity: the range-Doppler map.'];
'cfar',  'Detection', ['A fixed threshold would drown in false alarms or miss everything. CFAR estimates the local noise from neighbouring cells and adapts. Tune alpha, guard and training cells in the lab and watch the white squares react.'];
'usb',   'The product', ['Out of 800 million samples per second comes a handful of numbers: range, velocity, strength per detection - streamed over USB to the map display. That is a radar.'];
};
steps = struct('id', T(:,1), 'title', T(:,2), 'text', T(:,3));
end

% ---------------------------------------------------------------------
function blocks = block_db(p)
cCTRL = [0.80 0.92 0.80];  cTX  = [1.00 0.88 0.72];  cRF  = [0.92 0.92 0.92];
cCNV  = [0.97 0.85 0.85];  cDSP = [0.80 0.88 0.98];  cMEM = [0.93 0.87 0.99];
cOUT  = [1.00 0.97 0.75];
mdir = fullfile(fileparts(mfilename('fullpath')), '+aeris');
vdir = p.fpga_dir;
B = {
'stm32', {'STM32F746','supervisor'},     1   53  9    8  cCTRL  ''                                     ''
'chirp', {'PLFM chirp','generator'},    13   53 14    8  cTX    fullfile(mdir,'load_chirp_refs.m')     fullfile(vdir,'plfm_chirp_controller.v')
'dac',   {'DAC','AD9708'},              30   53 10    8  cCNV   ''                                     fullfile(vdir,'dac_interface_single.v')
'txrf',  {'TX RF chain','LTC5552+ADAR1000','+ADTR1107 PA'}, 43 53 16 8 cRF  ''                         ''
'ant',   {'Antenna array','8x16 / 32x16'},62 53 16    8  cRF    ''                                     ''
'rxrf',  {'RX RF chain','LNA \rightarrow IF 120 MHz'}, 62 37 16 8 cRF fullfile(mdir,'scene_generate_adc.m') ''
'adc',   {'ADC AD9484','8-bit 400 MSPS'},47 37 12    8  cCNV   ''                                     fullfile(vdir,'ad9484_interface_400m.v')
'mix',   {'I/Q mixer'},                 33   37 11    8  cDSP   fullfile(mdir,'ddc_chain.m')           fullfile(vdir,'ddc_400m.v')
'nco',   {'NCO 120 MHz'},               33   30 11    5  cDSP   fullfile(mdir,'nco_sincos.m')          fullfile(vdir,'nco_400m_enhanced.v')
'cic',   {'CIC \div4'},                 22   37  8.5  8  cDSP   fullfile(mdir,'ddc_chain.m')           fullfile(vdir,'cic_decimator_4x_enhanced.v')
'fir',   {'FIR 32-tap','+ 16-bit round'},11.5 37 8.5  8  cDSP   fullfile(mdir,'ddc_chain.m')           fullfile(vdir,'fir_lowpass.v')
'agc',   {'AGC gain'},                   1   37  8.5  8  cDSP   fullfile(mdir,'rx_gain_control.m')     fullfile(vdir,'rx_gain_control.v')
'cmem',  {'Chirp memory','4x1024 Q15'},  1   19 10    6.5 cMEM  fullfile(mdir,'load_chirp_refs.m')     fullfile(vdir,'chirp_memory_loader_param.v')
'mf',    {'Matched filter','1024-pt FFT'},13 19 13    8  cDSP   fullfile(mdir,'mf_multi_segment.m')    fullfile(vdir,'matched_filter_multi_segment.v')
'dec',   {'Range decim','1024\rightarrow64'},28 19 10 8  cDSP   fullfile(mdir,'range_bin_decimator.m') fullfile(vdir,'range_bin_decimator.v')
'mti',   {'MTI','2-pulse'},             40   19  8    8  cDSP   fullfile(mdir,'mti_canceller.m')       fullfile(vdir,'mti_canceller.v')
'dop',   {'Doppler FFT','2x16-pt'},     50   19 10    8  cDSP   fullfile(mdir,'doppler_process.m')     fullfile(vdir,'doppler_processor.v')
'notch', {'DC notch'},                  62   19  8    8  cDSP   fullfile(mdir,'dc_notch.m')            fullfile(vdir,'radar_system_top.v')
'cfar',  {'CA-CFAR'},                   72   19  8    8  cDSP   fullfile(mdir,'cfar_ca.m')             fullfile(vdir,'cfar_ca.v')
'usb',   {'USB / GUI','detections'},    82   19 10    8  cOUT   ''                                     fullfile(vdir,'usb_data_interface.v')
};
blocks = struct('id', B(:,1), 'label', B(:,2), 'x', B(:,3), 'y', B(:,4), ...
                'w', B(:,5), 'h', B(:,6), 'color', B(:,7), ...
                'mfile', B(:,8), 'vfile', B(:,9), 'spec', []);
for k = 1:numel(blocks)
    blocks(k).spec = spec_text(blocks(k).id, p);
end
end

function s = spec_text(id, p) %#ok<INUSD>
switch id
    case 'stm32'
        s = {
'STM32F746 SUPERVISOR'
'====================='
'Role: system management - NOT in the radar signal path.'
''
'  - Power-up/down sequencing of all rails'
'  - AD9523-1 clock generator + 2x ADF4382 synthesizer setup'
'  - 4x ADAR1000 phase shifters: beam steering + pulse sequencing'
'  - PA bias loop: 2x DAC5578 (Vg) / 2x ADS7830 (Idq via INA241A3)'
'  - GPS UM982, GY-85 IMU, BMP180 barometer, stepper, cooling'
'  - FPGA configuration via USB opcodes:'
'      0x01 mode | 0x10-0x15 chirp timing | 0x16 gain'
'      0x21-0x25 CFAR | 0x26 MTI | 0x27 DC notch | 0x28-0x2C AGC'
''
'Firmware: 9_Firmware/9_1_Microcontroller (C/C++)'
};
    case 'chirp'
        s = {
'PLFM CHIRP GENERATOR  (plfm_chirp_controller.v)'
'================================================'
'Waveform: pulse linear FM, B = 20 MHz (30 -> 10 MHz at IF)'
''
'  long chirp   30 us   3600 samples @ 120 MHz (8-bit LUT)'
'  long listen  137 us   -> PRI 167 us, x16 chirps'
'  guard        175.4 us'
'  short chirp  0.5 us  60 samples'
'  short listen 174.5 us -> PRI 175 us, x16 chirps'
'  frame: 32 chirps (staggered PRI), 31 elevations, 50 azimuths'
''
'Matched-filter references (100 MSPS baseband, Q15, 0.9 FS):'
'  phase = pi*(B/T)*t^2 ; long 3000 samples in 4 segments of 1024,'
'  short 50 samples; stored in long_chirp_seg0..3_{i,q}.mem'
''
'MATLAB: aeris.load_chirp_refs reads the same .mem files the FPGA'
'synthesis uses - single source of truth.'
};
    case 'dac'
        s = {
'TX DAC  AD9708  (dac_interface_single.v)'
'=========================================='
'  8-bit, offset binary (mid-scale 128 = 0 V), 120 MHz update'
'  Clock forwarded via ODDR primitive (near-zero skew)'
'  Idle/blanking value: 128'
'  -> reconstruction LPF (~60 MHz) -> LTC5552 up-conversion'
};
    case 'txrf'
        s = {
'TX RF CHAIN (analog, Main Board + PA boards)'
'=============================================='
'  LTC5552 double-balanced mixer: IF -> 10.5 GHz'
'  Stub BPF (RO4350B 102 um) - LO + image rejection'
'  4x ADAR1000: 4-channel phase shifters (TX beamforming,'
'    ~2.8 deg phase LSB, 0.5 dB gain steps)'
'  16x ADTR1107 front-end PA (AERIS-10N, ~1 W/ch)'
'  + 16x QPA2962 10 W GaN PA (AERIS-10X only)'
''
'Simulated at behavioural level: the scene generator produces the'
'IF-referred echo each TX pulse would create (radar_scene.py model).'
};
    case 'ant'
        s = {
'ANTENNA ARRAY'
'=============='
'  AERIS-10N: 8x16 microstrip patch array, RO4350B,'
'             24.3 dBi (CST), lambda/2 = 14.3 mm @ 10.5 GHz'
'  AERIS-10X: 32x16 alumina-filled slotted waveguide'
'  Steering:  elevation electronic +/-45 deg (16 channels),'
'             azimuth mechanical 360 deg (stepper)'
''
'EM simulation belongs to CST/HFSS (Simulation Plan phase 2);'
'this MATLAB suite covers the digital chain (phases 3.3 / 5).'
};
    case 'rxrf'
        s = {
'RX RF CHAIN (analog)'
'====================='
'  ADTR1107 LNA path -> ADAR1000 RX beamforming -> 16:1 combine'
'  LTC5552 down-conversion to IF = 120 MHz'
'  IF BPF 120-180 MHz -> IF amplifiers (PMA2-123LNW+/LTC6419)'
'  195 MHz differential anti-alias filter -> ADC'
''
'In this simulation the whole analog path is represented by the'
'scene model: each target adds a delayed, Doppler-shifted, scaled'
'copy of the chirp at 120 MHz IF + AWGN, quantized to 8 bits.'
'  amplitude = sqrt(RCS_lin)/R^2 * 100^2 * 64 LSB  (radar_scene.py)'
};
    case 'adc'
        s = {
'ADC  AD9484  (ad9484_interface_400m.v)'
'========================================'
'  8-bit, 400 MSPS, LVDS DDR: 8 data lanes + 400 MHz DCO'
'  IDDR capture, MMCM jitter cleaning, BUFG distribution'
'  Output: offset binary 0..255'
''
'Sign conversion happens in the DDC:'
'  adc_signed = (adc << 9) - 0xFF00     (18-bit)'
'  NOTE: mid-scale 128 maps to +256, a half-LSB DC bias that'
'  shows up as a near-DC Doppler ridge (host removes DC).'
};
    case 'nco'
        s = {
'NCO  (nco_400m_enhanced.v)  - bit-exact vs tb/nco_1mhz_output.csv'
'=================================================================='
'  32-bit phase accumulator; FTW = 0x4CCCCCCD -> 120 MHz @ 400 MSPS'
'  64-entry quarter-wave sine LUT, 16-bit (values in aeris_params)'
'  LUT address = phase[31:24]; quadrant = addr[7:6]'
'  Optional 8-bit LFSR phase dither (off in the golden models)'
''
'FINDING: mirror condition is quadrant[0] XOR quadrant[1] -> mirrors'
'quadrants 1 AND 2 (textbook DDS mirrors 1 and 3). In quadrants 2/3'
'sin and cos are swapped, so the output is discontinuous at 180 deg.'
'The model replicates this exactly; fixing it in RTL would lower'
'mixer spurs.'
};
    case 'mix'
        s = {
'I/Q MIXER  (ddc_400m.v, DSP48E1)'
'================================='
'  I = adc_signed * cos ,  Q = adc_signed * sin'
'  18 x 16 -> 34-bit product, keep bits [33:16] (wrap to 18-bit)'
'  No rounding, no gain compensation'
'  Products at f_sig +/- 120 MHz; the difference term is the'
'  complex baseband, the sum term is removed by CIC + FIR.'
};
    case 'cic'
        s = {
'CIC DECIMATOR  (cic_decimator_4x_enhanced.v) - bit-exact vs RTL dumps'
'======================================================================'
'  5 stages, R = 4 (400 -> 100 MSPS), differential delay 1'
'  Integrators: 48-bit wrapping (DSP48E1 cascade)'
'  Combs: 28-bit; gain 4^5 = 1024 normalized by >>>10; sat to 18-bit'
''
'  Equivalent FIR: conv(ones(1,4)) ^ 5  (16 taps, exact because the'
'  modular integrator arithmetic cancels while |out| < 2^27).'
'  Validated bit-exactly: impulse {9,634,1513,341}, DC, passband sine.'
};
    case 'fir'
        s = {
'FIR LOWPASS + 16-BIT INTERFACE  (fir_lowpass.v, ddc_input_interface.v)'
'======================================================================='
'  32 symmetric taps, 18-bit coefficients (see aeris_params.m)'
'  36-bit accumulator; saturate at +/-2^34, else output acc[34:17]'
'  Then 18 -> 16 bit: v[17:2] + v[1]  (round-half-up, 16-bit wrap)'
''
'  Passband covers the +/-10 MHz chirp; validated bit-exactly against'
'  fir_impulse / fir_dc / fir_sine RTL dumps (impulse response = the'
'  coefficient list scaled).'
};
    case 'agc'
        s = {
'DIGITAL GAIN / HYBRID AGC  (rx_gain_control.v)'
'==============================================='
'  Power-of-two gain on 16-bit I/Q: shift +/-7, saturate +/-32767'
'  Driven by the FPGA/STM32/GUI hybrid AGC loop:'
'    0x16 manual gain | 0x28 enable | 0x29 target (200)'
'    0x2A attack (1) | 0x2B decay (1) | 0x2C holdoff (4 frames)'
''
'FINDING: the forward FFTs have no stage scaling, so composite scenes'
'clip FFT bins unless this stage backs off. The demo uses gain -4'
'(divide by 16); with gain 0 the strongest scatterer saturated ~5% of'
'signal-FFT bins and its compression collapsed.'
''
'TRY IT: set "AGC gain" to 0 in the Scenario Lab and press Apply.'
};
    case 'cmem'
        s = {
'CHIRP REFERENCE MEMORY  (chirp_memory_loader_param.v)'
'======================================================'
'  Long: 4096 x 16-bit I + Q (4 segments x 1024), Q15, 0.9 FS'
'  Short: 1024 x 16-bit I + Q (50 valid, zero-padded by loader)'
'  Address = {segment[1:0], sample[9:0]}'
'  latency_buffer.v (3187 cycles) aligns reference with data'
''
'  Segment 2 ends with 24 pad zeros (chirp sample 3000);'
'  segment 3 is ALL zeros - echo energy in window 4 is matched'
'  against zeros and lost (as-built).'
};
    case 'mf'
        s = {
'MATCHED FILTER  (matched_filter_*.v, fft_engine.v) - 25/25 bit-exact'
'====================================================================='
'  Per segment: 1024-pt FFT(sig) -> x conj(FFT(ref)) -> IFFT'
'  FFT: radix-2 DIT, 32-bit internal, Q15 quarter-wave twiddles'
'       (fft_twiddle_1024.mem), butterfly product >>>15,'
'       forward output saturated to 16-bit (NO 1/N scaling),'
'       IFFT extra >>>10'
'  Conj multiply: (ac+bd) + j(bc-ad), round +2^14, keep [30:15]'
'  Segmentation: overlap-save, advance 896, full 1024 buffer,'
'       zero-pad after chirp sample 3000; input stored as'
'       (v >>> 2) + v[1]'
''
'FINDINGS:'
'  - committed multiseg goldens predate the overlap-save fix'
'    (model supports framing = "legacy" | "rtl")'
'  - independent segment processing compresses only ~6.8 MHz of the'
'    20 MHz chirp -> ~22 m peaks (vs 7.5 m full-BW) and the peak'
'    repeats +128 bins per segment'
'  - the 0.9-FS reference saturates ~230/1024 of its own FFT bins'
};
    case 'dec'
        s = {
'RANGE-BIN DECIMATOR  (range_bin_decimator.v) - bit-exact'
'========================================================='
'  1024 -> 64 bins, factor 16  (1.5 m -> 24 m per bin)'
'  Modes: 00 centre sample | 01 peak |I|+|Q| (receiver default)'
'         10 average (sum >>> 4)'
'  start_bin offset selects the region of interest'
'  Peak mode keeps the I/Q pair of the strongest cell (first max wins)'
};
    case 'mti'
        s = {
'MTI CANCELLER  (mti_canceller.v) - bit-exact'
'============================================='
'  2-pulse canceller per range bin: out = cur - prev,'
'  17-bit difference saturated to 16-bit'
'  First chirp muted (no history); enable = USB opcode 0x26'
'  H(z) = 1 - z^-1: null at 0 Hz -> removes stationary clutter'
''
'TRY IT: toggle "MTI clutter filt." in the Scenario Lab - the CFAR'
'and detection views switch instantly between the two paths.'
};
    case 'dop'
        s = {
'DOPPLER PROCESSOR  (doppler_processor.v) - bit-exact'
'====================================================='
'  Corner-turn memory: 64 range bins x 32 chirps (2 x BRAM18K)'
'  Dual 16-pt FFT: sub-frame 0 = chirps 0-15 (long PRI 167 us),'
'                  sub-frame 1 = chirps 16-31 (short PRI 175 us)'
'  16-pt Hamming window Q15, product rounded +2^14 then >>>15'
'  Output bin = {sub_frame, bin[3:0]}; 5.35 m/s per bin (long PRI)'
'  unambiguous +/-42.8 m/s'
''
'FINDING: sub-frame 1 only sees targets within ~50-75 m because the'
'short-chirp matched filter collects just 50 baseband samples.'
};
    case 'notch'
        s = {
'POST-DOPPLER DC NOTCH  (radar_system_top.v) - bit-exact'
'========================================================'
'  Zeros Doppler bins around DC in both sub-frames:'
'    bin_in_sf < width  OR  bin_in_sf > 15 - width + 1'
'  width 0 = off (host default), opcode 0x27'
'  width 2 zeros bins {0,1,15} and {16,17,31}'
''
'  Mitigates the DC ridge caused by the ADC half-LSB bias and'
'  truncation offsets accumulating across 16 chirps.'
''
'TRY IT: change "DC notch width" in the Scenario Lab and press Apply'
'(updates instantly from the cached Doppler maps).'
};
    case 'cfar'
        s = {
'CA / GO / SO CFAR  (cfar_ca.v) - bit-exact incl. detection list'
'================================================================'
'  Magnitude: |I| + |Q| (17-bit L1 norm)'
'  Sliding window down range per Doppler column:'
'    guard cells: 2/side (0x21) ; training: 8/side (0x22)'
'  threshold = alpha(Q4.4) * SUM(training) >>> 4, sat 131071'
'  detection: mag > threshold (strict) ; modes CA / GO / SO (0x24)'
''
'FINDING: default alpha = 0x30 means 3.0 x SUM of 16 cells = ~48x the'
'cell mean - effectively never fires. alpha = 0x08 (8x mean) detects'
'all demo targets. Edge cells use fewer training cells (Pfa rises).'
''
'TRY IT: sweep "CFAR alpha" in the Scenario Lab (instant update).'
'Lower alpha -> more detections AND more false alarms.'
};
    case 'usb'
        s = {
'USB STREAM / DETECTIONS  (usb_data_interface.v)'
'================================================'
'  FT601 (32-bit, 100 MHz) or FT2232H (8-bit, 60 MHz)'
'  Per range-Doppler cell, 3 x 32-bit words:'
'    word0: 0xAA | range I/Q bytes...'
'    word1: ...range | Doppler real/imag'
'    word2: ...| flags{frame_start, cfar} | 0x55 | pad'
'  2048 cells per frame (64 range x 32 Doppler)'
'  Consumed by the Python GUI (9_Firmware/9_3_GUI/v7, PyQt6)'
};
    otherwise
        s = {'(no specification)'};
end
s = [s; {''}; {'--- MATLAB suite: matlab/ | reference data: reference/fpga/ ---'}];
end
