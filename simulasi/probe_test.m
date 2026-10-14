clear;
close all;
clc;

addpath('/home/aziz-faozi/opt/openEMS/share/openEMS/matlab');
addpath('/home/aziz-faozi/opt/openEMS/share/CSXCAD/matlab');

unit = 1e-3;

CSX = InitCSX();

CSX = AddMetal(CSX,'PEC');

% =========================
% SUBSTRATE
% =========================
CSX = AddMaterial(CSX,'FR4');
CSX = SetMaterialProperty(CSX,'FR4','Epsilon',4.5);

CSX = AddBox(CSX,'FR4',1,...
    [0 0 -1.6],...
    [30 20 0]);

% =========================
% TOP MICROSTRIP
% =========================
CSX = AddBox(CSX,'PEC',10,...
    [5 9 0],...
    [25 11 0]);

% =========================
% BOTTOM GROUND
% =========================
CSX = AddBox(CSX,'PEC',10,...
    [0 0 -1.6],...
    [30 20 -1.6]);

% =========================
% MESH
% =========================
mesh.x = linspace(0,30,61);
mesh.y = linspace(0,20,41);
mesh.z = [-1.6 -1.5 -1.0 -0.5 0 0.5 1 2];

CSX = DefineRectGrid(CSX,unit,mesh);

% =========================
% MSL PORT
% =========================
start = [5 10 0];
stop  = [5 10 -1.6];

[CSX,port] = AddMSLPort(...
    CSX,100,1,'PEC',...
    start,stop,'x',[0 0 -1],...
    'ExcitePort',true,...
    'Feed_R',50,...
    'PortNamePrefix','TEST_');

% =========================
% FDTD
% =========================
FDTD = InitFDTD(...
    'NrTS',1000,...
    'EndCriteria',1e-5);

FDTD = SetGaussExcite(...
    FDTD,1.835e9,85e6);

FDTD = SetBoundaryCond(...
    FDTD,...
    {'PML_8','PML_8',...
     'PML_8','PML_8',...
     'PML_8','PML_8'});

% =========================
% WRITE
% =========================
Sim_Path = 'probe_test';

if ~exist(Sim_Path,'dir')
    mkdir(Sim_Path);
end

% XML berada di dalam Sim_Path
SimFile = 'probe_test.xml';

WriteOpenEMS([Sim_Path '/' SimFile],FDTD,CSX);

disp('Running openEMS...');
RunOpenEMS(Sim_Path,SimFile);

disp(' ');
disp('================ PORT ================');
disp(port);

disp(' ');
disp('================ FILES ================');
system(['find ' Sim_Path ' -type f -printf "%p\n" | sort']);

f = linspace(1.75e9,1.92e9,201);

port = calcPort(port,Sim_Path,f,'RefImpedance',50);

S11 = port.uf.ref ./ port.uf.inc;

disp(' ');
disp('===== PORT RESULT =====');
printf('Max |S11| = %.3f dB\n', ...
    20*log10(max(abs(S11))));

printf('S11 @ 1.835 GHz = %.3f dB\n', ...
    20*log10(abs(interp1(f,S11,1.835e9))));
