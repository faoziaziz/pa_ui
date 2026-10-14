clear;
close all;
clc;

% ============================================================
% openEMS paths
% ============================================================

addpath('/home/aziz-faozi/opt/openEMS/share/openEMS/matlab');
addpath('/home/aziz-faozi/opt/openEMS/share/CSXCAD/matlab');

% ============================================================
% Units
% ============================================================

unit = 1e-3;   % geometry is in mm

% ============================================================
% FDTD
% ============================================================

f0 = 1.8325e9;
fc = 0.150e9;

FDTD = InitFDTD( ...
    'NrTS', 20000, ...
    'EndCriteria', 1e-5);

FDTD = SetGaussExcite(FDTD, f0, fc);

BC = {'PML_8','PML_8','PML_8','PML_8','PML_8','PML_8'};
FDTD = SetBoundaryCond(FDTD, BC);

% ============================================================
% CSX
% ============================================================

CSX = InitCSX();

% ============================================================
% Materials
% ============================================================

CSX = AddMaterial(CSX, 'FR4');
CSX = SetMaterialProperty( ...
    CSX, ...
    'FR4', ...
    'Epsilon', 4.5, ...
    'Kappa', 0);

CSX = AddMetal(CSX, 'PEC');

% ============================================================
% Simple PCB
% ============================================================

% FR4:
% x = 0..59 mm
% y = 0..39 mm
% z = -1.545..-0.035 mm

CSX = AddBox( ...
    CSX, ...
    'FR4', ...
    1, ...
    [0 0 -1.545], ...
    [59 39 -0.035]);

% Bottom ground plane

CSX = AddBox( ...
    CSX, ...
    'PEC', ...
    10, ...
    [0 0 -1.580], ...
    [59 39 -1.545]);

% Simple top trace

CSX = AddBox( ...
    CSX, ...
    'PEC', ...
    10, ...
    [5 19.4 -0.035], ...
    [54 19.6 0]);

% ============================================================
% Mesh
% ============================================================

mesh.x = SmoothMeshLines( ...
    [0 5 54 59], ...
    2);

mesh.y = SmoothMeshLines( ...
    [0 19.4 19.6 39], ...
    2);

mesh.z = SmoothMeshLines( ...
    [-2 -1.580 -1.545 -0.035 0 1], ...
    0.2);

CSX = DefineRectGrid( ...
    CSX, ...
    unit, ...
    mesh);

% ============================================================
% Write XML
% ============================================================

Sim_Path = 'test_openems';
Sim_CSX = 'test_openems.xml';

if exist(Sim_Path, 'dir') ~= 7
    mkdir(Sim_Path);
end

WriteOpenEMS( ...
    [Sim_Path '/' Sim_CSX], ...
    FDTD, ...
    CSX);

fprintf('\n========================================\n');
fprintf('openEMS XML successfully generated.\n');
fprintf('========================================\n');
fprintf('File: %s/%s\n', Sim_Path, Sim_CSX);
