clear;
close all;
clc;

%% ============================================================
%  PA PCB - openEMS first-pass EM simulation
%
%  KiCad geometry -> openEMS
%
%  First validation:
%       J1 SMA -> QPA9418 RFIN
%
%  PCB:
%       F.Cu  = RF copper
%       FR4   = dielectric
%       B.Cu  = GND plane
%
%  RF net:
%       Net-(U1-RFIN)
%
%  Frequency:
%       1.75 - 1.92 GHz
%
%  Geometry unit:
%       mm
%
%  IMPORTANT:
%       Copper is represented as zero-thickness metal sheets
%       for first-pass EM validation.
%% ============================================================


%% ============================================================
% openEMS paths
%% ============================================================

addpath('/home/aziz-faozi/opt/openEMS/share/openEMS/matlab');
addpath('/home/aziz-faozi/opt/openEMS/share/CSXCAD/matlab');


%% ============================================================
% Simulation directory
%% ============================================================

Sim_Path = 'sim_J1_RFIN';

if ~exist(Sim_Path, 'dir')
    mkdir(Sim_Path);
end


%% ============================================================
% Simulation parameters
%% ============================================================

unit = 1e-3;              % geometry is in mm

f_start = 1.75e9;
f_stop  = 1.92e9;

f0 = (f_start + f_stop)/2;
fc = (f_stop - f_start)/2;

fprintf('\n');
fprintf('============================================\n');
fprintf('PA PCB openEMS simulation\n');
fprintf('============================================\n');

fprintf('Frequency range : %.3f - %.3f GHz\n', ...
        f_start/1e9, f_stop/1e9);

fprintf('Center frequency: %.3f GHz\n', ...
        f0/1e9);


%% ============================================================
% PCB stackup
%
% F.Cu
% z = 0
%
% FR4
% z = 0 ... -1.51 mm
%
% B.Cu
% z = -1.545 mm
%% ============================================================

cu_t  = 0.035;             % mm
fr4_t = 1.51;              % mm
eps_r = 4.5;

% Copper sheet positions
z_fcu = 0;

z_bcu = -(cu_t + fr4_t);

% Physical copper boundaries
z_fcu_bottom = z_fcu - cu_t;
z_bcu_top    = z_bcu;
z_bcu_bottom = z_bcu - cu_t;

fprintf('\n');
fprintf('PCB stackup:\n');

fprintf('  F.Cu sheet : z = %.4f mm\n', z_fcu);
fprintf('  FR4        : %.4f ... %.4f mm\n', ...
        z_bcu, z_fcu);

fprintf('  B.Cu sheet : z = %.4f mm\n', z_bcu);


%% ============================================================
% Load KiCad geometry
%% ============================================================

fprintf('\nLoading pcb_geometry.json...\n');

json_text = fileread('pcb_geometry.json');
pcb = jsondecode(json_text);


%% ============================================================
% Board dimensions
%% ============================================================

xmin = pcb.board.xmin;
xmax = pcb.board.xmax;

ymin = pcb.board.ymin;
ymax = pcb.board.ymax;

fprintf('Board size: %.3f x %.3f mm\n', ...
        xmax-xmin, ymax-ymin);

fprintf('Board limits:\n');
fprintf('  X = %.3f ... %.3f mm\n', xmin, xmax);
fprintf('  Y = %.3f ... %.3f mm\n', ymin, ymax);


%% ============================================================
% Initialize CSXCAD
%% ============================================================

fprintf('\nInitializing CSXCAD...\n');

CSX = InitCSX();


%% ============================================================
% Materials
%% ============================================================

fprintf('Creating materials...\n');

% FR4 dielectric
CSX = AddMaterial(CSX, 'FR4');

CSX = SetMaterialProperty( ...
    CSX, ...
    'FR4', ...
    'Epsilon', eps_r, ...
    'Kappa', 0);

% Copper
%
% For first-pass simulation copper is treated as PEC.
%
CSX = AddMetal(CSX, 'copper');


%% ============================================================
% FR4 substrate
%% ============================================================

fprintf('Adding FR4 substrate...\n');

CSX = AddBox( ...
    CSX, ...
    'FR4', ...
    1, ...
    [xmin ymin z_bcu], ...
    [xmax ymax z_fcu]);


%% ============================================================
% RF net definition
%% ============================================================

rf_net = 'Net-(U1-RFIN)';

fprintf('\n');
fprintf('RF validation net:\n');
fprintf('  %s\n', rf_net);


%% ============================================================
% F.Cu RF segments
%
% Only model the RFIN trace for this first validation.
%
% The complete PCB will be added later.
%% ============================================================

fprintf('\nAdding F.Cu RF segments...\n');

rf_segment_count = 0;

for k = 1:numel(pcb.segments)

    s = pcb.segments(k);

    % F.Cu only
    if ~strcmp(s.layer, 'F.Cu')
        continue;
    end

    % RFIN net only
    if ~strcmp(s.net, rf_net)
        continue;
    end

    x1 = s.start(1);
    y1 = s.start(2);

    x2 = s.xEnd(1);
    y2 = s.xEnd(2);

    w = s.width;

    % Ignore zero-length segments
    if hypot(x2-x1, y2-y1) < 1e-6
        continue;
    end

    % Segment vector
    dx = x2 - x1;
    dy = y2 - y1;

    L = hypot(dx,dy);

    % Normal vector
    nx = -dy/L * w/2;
    ny =  dx/L * w/2;

    % Rectangular polygon
    p = [
        x1+nx, y1+ny;
        x2+nx, y2+ny;
        x2-nx, y2-ny;
        x1-nx, y1-ny
    ];

    points = p';

    CSX = AddPolygon( ...
        CSX, ...
        'copper', ...
        20, ...
        'z', ...
        z_fcu, ...
        points);

    rf_segment_count = rf_segment_count + 1;

    fprintf( ...
        '  RF segment %d: %.4f %.4f -> %.4f %.4f, width %.4f mm\n', ...
        rf_segment_count, ...
        x1, y1, ...
        x2, y2, ...
        w);

end

fprintf('Total RF segments: %d\n', rf_segment_count);


%% ============================================================
% F.Cu GND zones
%
% Keep GND copper on top layer.
%% ============================================================

fprintf('\nAdding F.Cu GND zones...\n');

fcu_gnd_count = 0;

for k = 1:numel(pcb.zones)

    z = pcb.zones(k);

    if ~strcmp(z.layer, 'F.Cu')
        continue;
    end

    if isempty(z.polygon)
        continue;
    end

    if ~strcmp(z.net, 'GNDREF')
        continue;
    end

    points = z.polygon';

    CSX = AddPolygon( ...
        CSX, ...
        'copper', ...
        15, ...
        'z', ...
        z_fcu, ...
        points);

    fcu_gnd_count = fcu_gnd_count + 1;

    fprintf('  F.Cu GND zone %d: %d points\n', ...
            fcu_gnd_count, ...
            size(points,2));

end

fprintf('Total F.Cu GND zones: %d\n', ...
        fcu_gnd_count);


%% ============================================================
% B.Cu GND plane
%
% Use the actual KiCad B.Cu GND zone.
%% ============================================================

fprintf('\nAdding B.Cu GND plane...\n');

bcu_gnd_count = 0;

for k = 1:numel(pcb.zones)

    z = pcb.zones(k);

    if ~strcmp(z.layer, 'B.Cu')
        continue;
    end

    if isempty(z.polygon)
        continue;
    end

    if ~strcmp(z.net, 'GNDREF')
        continue;
    end

    points = z.polygon';

    CSX = AddPolygon( ...
        CSX, ...
        'copper', ...
        15, ...
        'z', ...
        z_bcu, ...
        points);

    bcu_gnd_count = bcu_gnd_count + 1;

    fprintf('  B.Cu GND zone %d: %d points\n', ...
            bcu_gnd_count, ...
            size(points,2));

end

fprintf('Total B.Cu GND zones: %d\n', ...
        bcu_gnd_count);


%% ============================================================
% GND vias
%
% Connect F.Cu -> B.Cu.
%
% Since copper sheets are zero thickness in this first-pass
% model, the via spans from z_bcu to z_fcu.
%% ============================================================

fprintf('\nAdding GND vias...\n');

gnd_via_count = 0;

for k = 1:numel(pcb.vias)

    v = pcb.vias(k);

    if ~strcmp(v.net, 'GNDREF')
        continue;
    end

    x = v.x;
    y = v.y;

    r = v.diameter / 2;

    CSX = AddCylinder( ...
        CSX, ...
        'copper', ...
        30, ...
        [x y z_bcu], ...
        [x y z_fcu], ...
        r);

    gnd_via_count = gnd_via_count + 1;

end

fprintf('Total GND vias: %d\n', ...
        gnd_via_count);


%% ============================================================
% Print RF geometry
%% ============================================================

fprintf('\n');
fprintf('============================================\n');
fprintf('RF geometry\n');
fprintf('============================================\n');

for k = 1:numel(pcb.segments)

    s = pcb.segments(k);

    if strcmp(s.layer,'F.Cu') && ...
       strcmp(s.net,rf_net)

        fprintf( ...
            '  %.4f %.4f -> %.4f %.4f, width %.4f mm\n', ...
            s.start(1), ...
            s.start(2), ...
            s.xEnd(1), ...
            s.xEnd(2), ...
            s.width);

    end

end


%% ============================================================
% Mesh
%
% Important:
%
% Do NOT resolve 35 um copper thickness.
%
% Copper is represented as a sheet, therefore the mesh can
% remain at practical EM dimensions.
%% ============================================================

fprintf('\n');
fprintf('Creating mesh...\n');


fprintf('\nCreating mesh...\n');

% Force all coordinates to row vectors/scalars
xmin = xmin(1);
xmax = xmax(1);
ymin = ymin(1);
ymax = ymax(1);

% Important RF locations
x_rf = [
    104.9125, ...
    128.4250, ...
    128.4850
];

y_rf = 90.5000;

% Air margin around PCB
air_xy = 10.0;

xmin_mesh = xmin - air_xy;
xmax_mesh = xmax + air_xy;
ymin_mesh = ymin - air_xy;
ymax_mesh = ymax + air_xy;

% X mesh
mesh.x = [
    linspace(xmin_mesh, xmin, 20), ...
    linspace(xmin, xmax, 120), ...
    linspace(xmax, xmax_mesh, 20), ...
    x_rf
];

% Y mesh
mesh.y = [
    linspace(ymin_mesh, ymin, 15), ...
    linspace(ymin, ymax, 100), ...
    linspace(ymax, ymax_mesh, 15), ...
    y_rf
];

% Z mesh
%
% PCB:
%   B.Cu = -1.545 mm
%   F.Cu =  0 mm
%
% Provide sufficient air above/below the PCB
% so PML_8 has enough mesh lines.

mesh.z = [
    linspace(-12.0, -4.0, 17), ...
    linspace(-4.0, -2.0, 9), ...
    -1.5450, ...
    -1.25, ...
    -1.00, ...
    -0.75, ...
    -0.50, ...
    -0.25, ...
     0.0000, ...
     0.25, ...
     0.50, ...
     0.75, ...
     1.00, ...
     1.50, ...
     2.00, ...
     3.00, ...
     4.00, ...
    linspace(5.0, 12.0, 15)
];

% Remove duplicate coordinates and sort
mesh.x = unique(sort(mesh.x));
mesh.y = unique(sort(mesh.y));
mesh.z = unique(sort(mesh.z));

% Force row vectors
mesh.x = mesh.x(:).';
mesh.y = mesh.y(:).';
mesh.z = mesh.z(:).';

fprintf('Mesh X lines: %d\n', length(mesh.x));
fprintf('Mesh Y lines: %d\n', length(mesh.y));
fprintf('Mesh Z lines: %d\n', length(mesh.z));

fprintf('Mesh X range: %.3f ... %.3f mm\n', ...
        mesh.x(1), mesh.x(end));

fprintf('Mesh Y range: %.3f ... %.3f mm\n', ...
        mesh.y(1), mesh.y(end));

fprintf('Mesh Z range: %.3f ... %.3f mm\n', ...
        mesh.z(1), mesh.z(end));

% Check required PCB planes
fprintf('z_BCu = %.4f mm\n', z_bcu);
fprintf('z_FCu = %.4f mm\n', z_fcu);

CSX = DefineRectGrid(CSX, unit, mesh);

fprintf('Mesh successfully created.\n');
%% ============================================================
% Define CSX grid
%% ============================================================

CSX = DefineRectGrid( ...
    CSX, ...
    unit, ...
    mesh);


%% ============================================================
% MSL ports
%
% Port 1:
%       J1 SMA side
%
% Port 2:
%       before QPA9418 RFIN pad
%
% This is NOT yet the PA gain measurement.
%
% It only validates the PCB interconnect.
%% ============================================================

fprintf('\n');
fprintf('Creating MSL ports...\n');

port = {};

y_rf = 90.5;


%% ============================================================
% Port 1 - J1
%% ============================================================

x_p1 = 106.0;

start = [
    x_p1 ...
    y_rf ...
    z_fcu
];

stop = [
    x_p1 ...
    y_rf ...
    z_bcu
];

[CSX, port{1}] = AddMSLPort( ...
    CSX, ...
    100, ...
    1, ...
    'copper', ...
    start, ...
    stop, ...
    'x', ...
    [0 0 -1], ...
    'ExcitePort', true, ...
    'Feed_R', 50, ...
    'PortNamePrefix', 'J1_' );


fprintf('  Port 1 = J1, x = %.4f mm\n', x_p1);


%% ============================================================
% Port 2 - QPA9418 RFIN side
%% ============================================================

x_p2 = 127.0;

start = [
    x_p2 ...
    y_rf ...
    z_fcu
];

stop = [
    x_p2 ...
    y_rf ...
    z_bcu
];

[CSX, port{2}] = AddMSLPort( ...
    CSX, ...
    100, ...
    2, ...
    'copper', ...
    start, ...
    stop, ...
    'x', ...
    [0 0 -1], ...
    'ExcitePort', false, ...
    'Feed_R', 50, ...
    'PortNamePrefix', 'RFIN_' );


fprintf('  Port 2 = RFIN observation, x = %.4f mm\n', x_p2);


%% ============================================================
% FDTD
%% ============================================================

fprintf('\n');
fprintf('Creating FDTD setup...\n');

FDTD = InitFDTD( ...
    'NrTS', 30000, ...
    'EndCriteria', 1e-5);


%% ============================================================
% Gaussian excitation
%% ============================================================

FDTD = SetGaussExcite( ...
    FDTD, ...
    f0, ...
    fc);


%% ============================================================
% Boundary conditions
%% ============================================================

FDTD = SetBoundaryCond( ...
    FDTD, ...
    {
        'PML_8'
        'PML_8'
        'PML_8'
        'PML_8'
        'PML_8'
        'PML_8'
    });


%% ============================================================
% Write XML
%% ============================================================

SimFile = [Sim_Path '/pa_openems.xml'];

fprintf('\n');
fprintf('Writing openEMS XML:\n');
fprintf('  %s\n', SimFile);

WriteOpenEMS( ...
    SimFile, ...
    FDTD, ...
    CSX);

fprintf('XML created successfully.\n');


%% ============================================================
% Run openEMS
%% ============================================================

fprintf('\n');
fprintf('============================================\n');
fprintf('Running openEMS\n');
fprintf('============================================\n');

RunOpenEMS( ...
    Sim_Path, ...
    'pa_openems.xml');


fprintf('\n');
fprintf('Simulation finished.\n');


%% ============================================================
% Calculate port data
%% ============================================================

fprintf('\n');
fprintf('Calculating port data...\n');

f = linspace( ...
    f_start, ...
    f_stop, ...
    501);


port{1} = calcPort( ...
    port{1}, ...
    Sim_Path, ...
    f, ...
    'RefImpedance', 50);


port{2} = calcPort( ...
    port{2}, ...
    Sim_Path, ...
    f, ...
    'RefImpedance', 50);


%% ============================================================
% S-parameters
%
% S11:
%   reflected / incident at J1
%
% S21:
%   transmitted wave at Port 2 / incident wave at Port 1
%% ============================================================

S11 = port{1}.uf.ref ./ ...
      port{1}.uf.inc;

S21 = port{2}.uf.inc ./ ...
      port{1}.uf.inc;


S11_dB = 20*log10(abs(S11));

S21_dB = 20*log10(abs(S21));


%% ============================================================
% Print key results
%% ============================================================

idx_1835 = find( ...
    abs(f - 1.835e9) == ...
    min(abs(f - 1.835e9)), ...
    1);


fprintf('\n');
fprintf('============================================\n');
fprintf('RESULTS\n');
fprintf('============================================\n');

fprintf( ...
    'S11 @ 1.835 GHz = %.3f dB\n', ...
    S11_dB(idx_1835));

fprintf( ...
    'S21 @ 1.835 GHz = %.3f dB\n', ...
    S21_dB(idx_1835));

fprintf( ...
    'Max S11 over band = %.3f dB\n', ...
    max(S11_dB));

fprintf( ...
    'Min S21 over band = %.3f dB\n', ...
    min(S21_dB));



%% ============================================================
% Plot and save S11
%% ============================================================

fig_s11 = figure;

plot( ...
    f/1e9, ...
    S11_dB, ...
    'LineWidth', 1.5);

grid on;

xlabel('Frequency (GHz)');
ylabel('S_{11} (dB)');

title( ...
    'PA PCB - J1 to QPA9418 RFIN');

xlim([
    f_start ...
    f_stop
]/1e9);

% Save S11 plot
print( ...
    fig_s11, ...
    [Sim_Path '/S11_J1_RFIN.png'], ...
    '-dpng', ...
    '-r300');

print( ...
    fig_s11, ...
    [Sim_Path '/S11_J1_RFIN.pdf'], ...
    '-dpdf');

fprintf('S11 plot saved:\n');
fprintf('  %s/S11_J1_RFIN.png\n', Sim_Path);
fprintf('  %s/S11_J1_RFIN.pdf\n', Sim_Path);


%% ============================================================
% Plot and save S21
%% ============================================================

fig_s21 = figure;

plot( ...
    f/1e9, ...
    S21_dB, ...
    'LineWidth', 1.5);

grid on;

xlabel('Frequency (GHz)');
ylabel('S_{21} (dB)');

title( ...
    'PA PCB - J1 to QPA9418 RFIN');

xlim([
    f_start ...
    f_stop
]/1e9);

% Save S21 plot
print( ...
    fig_s21, ...
    [Sim_Path '/S21_J1_RFIN.png'], ...
    '-dpng', ...
    '-r300');

print( ...
    fig_s21, ...
    [Sim_Path '/S21_J1_RFIN.pdf'], ...
    '-dpdf');

fprintf('S21 plot saved:\n');
fprintf('  %s/S21_J1_RFIN.png\n', Sim_Path);
fprintf('  %s/S21_J1_RFIN.pdf\n', Sim_Path);




%% ============================================================
% Save results
%% ============================================================

save( ...
    'pa_rfin_results.mat', ...
    'f', ...
    'S11', ...
    'S21', ...
    'S11_dB', ...
    'S21_dB', ...
    'port');


%% ============================================================
% Final
%% ============================================================

fprintf('\n');
fprintf('============================================\n');
fprintf('Simulation complete.\n');
fprintf('============================================\n');

fprintf('Result file:\n');
fprintf('  pa_rfin_results.mat\n');

fprintf('\nSimulation directory:\n');
fprintf('  %s\n', Sim_Path);

