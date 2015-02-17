function [utraj, xtraj, prog, r] = runDircol(xf, tf0, bounds_delta, u0)
  % run trajectory optimization
  
  javaaddpath('/home/abarry/realtime/LCM/LCMtypes.jar');
  javaaddpath('/home/abarry/Fixie/build/share/java/lcmtypes_mav-lcmtypes.jar');
  
  checkDependency('lcmgl');
  lcmgl = drake.util.BotLCMGLClient(lcm.lcm.LCM.getSingleton(),'deltawing-dircol');
  
  lcmgl_f = drake.util.BotLCMGLClient(lcm.lcm.LCM.getSingleton(),'deltawing-dircol-final-condition');

  %% setup

  parameters = { 1.92, 1.84, 2.41, 0.48, 0.57 };

  x = 0;
  y = 0;
  z = 0;
  roll = 0;
  pitch = 0;
  yaw = 0;
  xdot = 15;
  ydot = 0;
  zdot = 0;
  rolldot = 0;
  pitchdot = 0;
  yawdot = 0;

  x0_drake = [ x; y; z; roll; pitch; yaw; xdot; ydot; zdot; rolldot; pitchdot; yawdot ]
  
  if nargin < 2
    tf0 = 0.5;
  end


  %% build drake objects

  p = DeltawingPlant(parameters);


  options.floating = true;
  r = RigidBodyManipulator('TBSC_visualizer.urdf', options);

  v2 = HudBotVisualizer(r);
  %v2 = r.constructVisualizer();
  
  %% draw final state
  
  lcmgl_f.glColor4f(1,0,0,.5);
  lcmgl_f.box(xf(1:3), 2*bounds_delta(1:3));
  
  lcmgl_f.switchBuffers();

  %% run trajectory optimization

  N = 11; % number of knot points
  minimum_duration = 0.1;
  maximum_duration = 2.0;

  prog = DircolTrajectoryOptimization(p, N, [minimum_duration, maximum_duration]);
  
  if (nargin < 4)
    u0 = [0, 0, 0];
  end
  
  prog = prog.addStateConstraint(ConstantConstraint(x0_drake), 1);
  prog = prog.addInputConstraint(ConstantConstraint(u0), 1);

%   xf = x0_drake;
% 
%   xf(1) = 15;
%   xf(2) = 0;
%   xf(3) = -3.68;
%   
%   xf(4) = 0;
%   xf(5) = .51;
%   xf(6) = 0;
%   
%   xf(7) = 14.95;
%   xf(8) = 0;
%   xf(9) = -8.42;
%   
%   xf(10) = 0;
%   xf(11) = 0.48;
%   xf(12) = 0;
  
  if nargin < 1
     xf = [14.9949
           1.5
     1
           deg2rad(60)
      0.5169
           0
     14.9585
           0
     -8.4280
           0
      0.2872
           0];
  end
  
  if nargin < 3
    bounds_delta = [.5
      .5
      .5
        deg2rad(5)
        deg2rad(5)
        deg2rad(5)
      2
      2
      2
      100
      100
      100];
  end

  prog = prog.addStateConstraint(BoundingBoxConstraint(xf-bounds_delta, xf+bounds_delta), N);
  %prog = prog.addInputConstraint(ConstantConstraint(u0), N);

  prog = prog.addRunningCost(@cost);
  
  final_cost = FunctionHandleConstraint(-inf, inf, 12, @finalCost, 0);
  final_cost.grad_method = 'numerical';
  prog = prog.addCost(final_cost, prog.x_inds(:,N));
  
  %prog = prog.addFinalCost(@finalCost);
  
  prog = prog.addTrajectoryDisplayFunction(@plotDircolTraj);
  
  prog = prog.setSolverOptions('snopt','print','print.out');

  
  traj_init.x = PPTrajectory(foh([0, tf0], [x0_drake, xf]));
  traj_init.u = ConstantTrajectory(u0);

  info = 0;

  disp('Starting trajectory optimization...');
  %while (info~=1)
    tic
    [xtraj, utraj, z, F, info] = prog.solveTraj(tf0, traj_init);
    toc
    keyboard;
  %end
  
%   for i=1:100000
%     disp(i)
%     pause(1)
%   end


  %% visualize

  % combine the simulated trajectory with the inputs

  traj_and_u = [xtraj; utraj];

  fr = traj_and_u.getOutputFrame();

  transform_func = @(t, x, x_and_u) [ x_and_u(1:6); x_and_u(15); x_and_u(13:14); x_and_u(7:12); zeros(3,1)];

  trans = FunctionHandleCoordinateTransform(17, 0, traj_and_u.getOutputFrame(), v2.getInputFrame(), true, true, transform_func, transform_func, transform_func);

  fr.addTransform(trans);


  playback(v2, traj_and_u, struct('slider', true));
  
  assert(info == 1, 'Trajectory optimization failed to find a solution.')
  
  DrawTrajectoryLcmGl(xtraj);
  

  function [g,dg] = cost(dt,x,u)

    R = 0.1*eye(3);
    R(3,3) = 0; % low cost on throttle action
    g = u'*R*u;
    %g = sum((R*u).*u,1);
    dg = [zeros(1,1+size(x,1)),2*u'*R];
    %dg = zeros(1, 1 + size(x,1) + size(u,1));

  end

  function [h] = finalCost(x)

    h = 0;
    
    %h = 20 * sum((xf(1:3) - x(1:3)).^2);
    
    %h = h + 1 * sum((xf(4:9) - x(4:9)).^2);
    
    %dh = [1,zeros(1,size(x,1))];

  end

  


  function plotDircolTraj(t,x,u)
    lcmgl.glColor3f(0,0,1);
    lcmgl.glLineWidth(2);

    last_knot = [];

    for knot = x
      lcmgl.sphere(knot, 0.05, 20, 20);

      if ~isempty(last_knot)
        lcmgl.line3(last_knot(1), last_knot(2), last_knot(3), knot(1), knot(2), knot(3));
      end

      last_knot = knot;
    end

    lcmgl.switchBuffers();
    
    
%     keyboard
    
  end

end
