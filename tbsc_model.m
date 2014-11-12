function [xdot,y] = tbsc_model(t,x,u,varargin) % Jx_fac,Jy_fac,Jz_fac,elev_lift_fac,F_Q_fac_x,F_Q_fac_z,thr_to_sp_ail,thr_vel_fac_ail,thr_to_sp_elev,thr_vel_fac_elev,varargin) % M_P_fac,M_Q_fac,M_R_fac,varargin) 
% Model derived from Ani's SBach model

% Set output (first six states)
y = x(1:6);


% @param t time
% @param x state: x =
%  Plane's X coordinate faces forward, Y to the right, and Z down.
%  x(1):x    (Forward Position, Earth frame)
%  x(2):y    (East or y position, Earth frame)
%  x(3):z     (z position (down), Earth frame)
%  x(4):phi   (roll angle)
%  x(5):theta (pitch angle)
%  x(6):psi   (yaw angle)
%  x(7):U     (X-velocity, body frame)
%  x(8):V     (Y-velocity, body frame)
%  x(9):W     (Z-velocity, body frame)
%  x(10):P    (Angular velocity in X direction, body frame)
%  x(11):Q    (Angular velocity in Y direction, body frame)
%  x(12):R    (Angular velocity in Z direction, body frame)
%
%  u(1):elevL   (Elevon left Command)
%  u(2):elevR   (Elevon right Command)
%  u(3):thr   (Throttle command)

%% Parameters fit from data %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Rotational inertias
Jx_fac = 1;
Jy_fac = 1;
Jz_fac = 1;

% Throttle/propwash
thr_fac = 1;

% Elevator
elevL_lift_fac = 1;
elevR_lift_fac = 1;

% Stabilizer
%stab_force_fac = 1;

% Body drag
body_x_drag_fac = 0;
body_y_drag_fac = 0;
body_z_drag_fac = 0;

% Rate dependent force
F_Q_fac_x = -0.1087;
F_Q_fac_z = 0.3230;

% Throttle aerodynamic drag
thr_drag_fac = 0; % thr_drag_fac*1e-6;

% Rate dependent moments
M_P_fac = 0;
M_Q_fac = 0;
M_R_fac = 0;


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Rotational inertias
Jx = Jx_fac*0.014894; % The numbers are from the solidworks model
Jy = Jy_fac*0.005580;
Jz = Jz_fac*0.019316;

J = diag([Jx,Jy,Jz]);
invJ = diag([1/Jx,1/Jy,1/Jz]);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Measured parameters (MKS units):
wing_area = 0.1811;% m^2
%out_dist = 132.8/1000; % Moment arm of outer wing section
%in_dist = 46.4/1000; % Moment arm of inner wing section
%ail_out_dist_x = 41/1000; % These are behind the COM 
%ail_in_dist_x = 65/1000; % These are behind the COM
elevL_area = 0.0125; % m^2
elevR_area = 0.0125;
elevL_arm = 280/1000;
elevR_arm = 280/1000;

%rudder_area = (3.80152*1000)/(1000*1000);
%rudder_arm = 258.36/1000; % m
%stab_area = 923.175/(1000*1000); % m^2
%stab_arm = 222/1000; % m
m =  0.648412; % kg (with battery in)
g = 9.81; % m/s^2
thr_to_thrust = 0.05159; % kg per unit throttle command TODO CHECK THIS IS KG NOT GRAMS

elevL_comm_to_rad = 8.430084159809215e-04; % TODO FIXME % Multiply raw command by these to get deflection in rads
elevR_comm_to_rad = 8.430084159809215e-04; % TODO FIXME

thr_min = 0; % If it's less than 270, prop doesn't spin

throttle_trim = 0; % At 250, we have 0 propwash speed (according to fit from anemometer readings)
elevL_trim = 0;
elevR_trim = 0;
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Get states
rpy = x(4:6);
% phi = rpy(1);
% theta = rpy(2);
% psi = rpy(3);
%% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
U = x(7);
V = x(8);
W = x(9);
P = x(10);
Q = x(11);
R = x(12);

R_body_to_world = rpy2rotmat(rpy);
R_world_to_body = R_body_to_world';

% COM velocity in world coordinates
xdots_world = R_body_to_world*[U;V;W];

% Angular velocity in world coordinate frame
omega_world = R_body_to_world*[P;Q;R];
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Get control inputs

%Throttle signal is 150-850
thr = u(3) - throttle_trim; % Shift it
if thr < (thr_min - throttle_trim)
    thr = 0;
end
% thr = thr_fac*max(thr,0); % Scale it and don't let it go negative

% positive AilL is negative lift (front of aileron tips downwards)
elevL = (u(1)-elevL_trim)*elevL_comm_to_rad; % input in radians of deflection
elevR = (u(2)-elevR_trim)*elevR_comm_to_rad; % input in radians of deflection

%positive elevator is deflection up (negative lift - makes plane
%pitch up)
%elev = (u(3)-elev_trim)*elev_comm_to_rad; % input in radians of deflection

%positive rudder is deflection to the right
%rud = (u(4)-rud_trim)*rud_comm_to_rad;% input in radians of deflection
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Now, the hard stuff

% Do translataional stuff first

% Speed of plane
vel = sqrt(U^2 + V^2 + W^2);

% Angle of attack
alpha = atan2(W,U);


%%Forces due to wings and elevons%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


%Lift force generated by wing components. (flat plate)
%lift = dynamic pressure * area * Coefficient of lift.
wing_lift = pressure(vel) * wing_area * Cl_fp_fit(alpha);



%Drag force generated by wing components.
wing_drag = pressure(vel) * wing_area * Cd_fp_fit(alpha);

% Collect these forces and represent them in correct frame
F_wing = rotAlpha([wing_drag; 0; wing_lift], alpha);
%F_elevL = rotAlpha([elevL_drag; 0; elevL_lift], alpha);


%F_right_wing_out = rotAlpha([right_wing_out_drag;0;right_wing_out_lift],alpha);
%F_right_ail_out = rotAlpha([right_ail_out_drag;0;right_ail_out_lift],alpha);
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Forces due to elevator

% Propwash over rudder/elevator (0.1444 was fit from anemometer
% experiments)
%upe = sqrt((vel^2)/4 + thr_to_sp_elev*0.1444*thr) - vel/2;

%Lift force generated by elevons. (flat plate)
%lift = dynamic pressure * area * Coefficient of lift.
% Velocity of elevator in world coordinate frame
xdot_elevL = xdots_world + cross(omega_world,[-elevL_arm;0;0]);
xdot_elevL_body = R_world_to_body*xdot_elevL;

xdot_elevR = xdots_world + cross(omega_world,[-elevR_arm;0;0]);
xdot_elevR_body = R_world_to_body*xdot_elevR;

alpha_elevL = atan2(xdot_elevL_body(3),xdot_elevL_body(1)); % TODO: CHECKME: SIGN
alpha_elevR = atan2(xdot_elevR_body(3),xdot_elevR_body(1)); % TODO: CHECKME: SIGN

%include lift terms from flat plate theory of elevator
elevL_lift = elevL_lift_fac*pressure(vel) * elevL_area * ... likely a small term % TODO MAKE SURE THAT PRESSURE(VEL) NOT PRESSURE(UPE/uwa) IS CORRECT
    Cl_fp(alpha_elevL-elevL); %angle of deflection of Elevator
  
elevR_lift = elevR_lift_fac*pressure(vel) * elevR_area * ... likely a small term % TODO MAKE SURE THAT PRESSURE(VEL) NOT PRESSURE(UPE) IS CORRECT
    Cl_fp(alpha_elevR-elevR); %angle of deflection of Elevator

%Compute drag on elevator using flat plate theory
elevL_drag = pressure(vel) * elevL_area * Cd_fp(alpha_elevL-elevL); % TODO: pressure(vel) instead of pressure(uwa) OK?
elevR_drag = pressure(vel) * elevR_area * Cd_fp(alpha_elevR-elevR); % TODO: pressure(vel) instead of pressure(uwa) OK?

% Rotate to correct frame
F_elevL = rotAlpha([elevL_drag; 0; elevL_lift], alpha_elevL); % elevon left
F_elevR = rotAlpha([elevR_drag; 0; elevR_lift], alpha_elevR); % elevon right
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Rudder and stabilizer

%Stabilizing force from aircraft yawing (this is a crude approximation)
%F_stabilizer = [0;-stab_force_fac*sign(R) * pressure(R*stab_arm) * (stab_area+rudder_area);0];

% Sideslip angle for rudder
%beta_rud = atan2(V,sqrt(vel^2-V^2) + upe); % Assuming propwash over rudder is same as elevator

% Rudder force flat plate
%rudder_force_l = pressure(uwe) * rudder_area * Cl_fp(beta_rud + rud);
%rudder_force_d = pressure(uwe) * rudder_area * Cd_fp(beta_rud + rud);

%rudder_force = [rudder_force_d;rudder_force_l;0];

% Rotate to correct frame
%F_rudder = [-cos(beta_rud), sin(beta_rud), 0; -sin(beta_rud), -cos(beta_rud), 0;0 0 0]*rudder_force;
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Gravity, thrust, and body drag
F_gravity = R_world_to_body*[0;0;m*g];

F_thrust = thr_fac*thr_to_thrust*g/1000; % thr_to_thrust was estimated from digital scale experiments

% Drag due to body (in x-direction)
body_drag_x =  body_x_drag_fac*pressure(U);

% Drag due to body in y-direction
body_drag_y = body_y_drag_fac * pressure(V) * wing_area; % Just a rough initial estimate

% Drag due to wing in z-direction
body_drag_z = body_z_drag_fac * pressure(W) * wing_area;

F_body_drag = [body_drag_x;-sign(V)*body_drag_y;-sign(W)*body_drag_z];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Additional angular rate dependent forces
F_rate_dependent = [F_Q_fac_x*Q;0;F_Q_fac_z*Q]; % These should be small effects hopefully

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Now moments/rotational stuff

% Moment from wings and ailerons
d_wing = [0; 0; 0]; % TODO, I think this is 0 because the wing is centered at the COM

M_wing = cross(d_wing, F_wing);

% Moment from elevator
d_elevL = [-elevL_arm; 0; 0];
d_elevR = [-elevR_arm; 0; 0];

M_elevL = cross(d_elevL, F_elevL);
M_elevR = cross(d_elevR, F_elevR);

% Moment from stabilizer
%d_stabilizer = [-stab_arm;0;-35/1000]; % -35 mm in z approximately
%M_stabilizer = cross(d_stabilizer,F_stabilizer);

% Moment from rudder
%d_rudder = [-rudder_arm;0;-9/1000]; % -9 mm in z approximately
%M_rudder = cross(d_rudder,F_rudder);

% Moment from throttle aerodynamic drag
M_throttle = [thr_drag_fac*thr; 0; 0];

% Additional rate dependent moments
M_rate_dependent = [M_P_fac*P; M_Q_fac*Q; M_R_fac*R];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Put equations together

% Kinematics
xyzdot = R_body_to_world*[U;V;W];
Phi = angularvel2rpydotMatrix(rpy);
rpydot = Phi*omega_world;

% Dynamics
% Translational equations
F_total = F_wing + ... % wing
          F_elevL + F_elevR + ... % + F_stabilizer + F_rudder + ... % elevator, stabilizer, rudder
          F_gravity + F_thrust + F_body_drag + F_rate_dependent; % gravity, thrust, body drag, rate dependent force

Sw = [0 -R Q; R 0 -P;-Q P 0];
UVW_dot = -Sw*[U;V;W] + F_total/m;

% Rotational stuff
M_total = M_wing + ...
          M_elevL + M_elevR + ... %M_stabilizer + M_rudder + 
          M_throttle + M_rate_dependent;
        
PQR_dot = invJ*(M_total - cross([P;Q;R],J*[P;Q;R]));


xdot = [xyzdot;rpydot;UVW_dot;PQR_dot];


end

function cl = Cl_fp(a) % Flat plate model
if a > pi/2
    a = pi/2;
elseif a<-pi/2
    a = -pi/2;
end

cl = 2*sin(a)*cos(a);

end

function cd = Cd_fp(a) % Flat plate
if a > pi/2
    a = pi/2;
elseif a<-pi/2
    a = -pi/2;
end

cd = 2*(sin(a)^2);

end

function cl = Cl_fp_fit(a) % Flat plate model with correction terms
if a > pi/2
    a = pi/2;
elseif a<-pi/2
    a = -pi/2;
end

% These numbers were fit from no-throttle experiments
cl = 2*sin(a)*cos(a) + 0.5774*sin(3.0540*a);

end

function cd = Cd_fp_fit(a) % Flat plate with correction terms
if a > pi/2
    a = pi/2;
elseif a<-pi/2
    a = -pi/2;
end

% These numbers were fit from no-throttle experiments
cd = 2*(sin(a)^2) - 0.1027*(sin(a)^2) + 0.1716;  % TODO: CHECKME

end

function f = rotAlpha(f,a)
% Rotation matrix
Ra = [-cos(a) 0  sin(a); ...
       0      0  0     ; ...
      -sin(a) 0 -cos(a)];

% Rotate f using Ra
f = Ra*f;  
end


% function cm = Cm(obj,a) % xfoil
% if a > pi/2
%     a = pi/2;
% elseif a<-pi/2
%     a = -pi/2;
% end
% 
% cm = ppval(obj.Cmpp, a*180/pi);
% end

function pre = pressure(vel) %Dynamic Pressure = .5 rho * v^2
  % rho = 1.1839; % kg/m^3 (density of air)
pre = .5 * 1.1839 * vel^2; % N/m^2
end
