function [ds] = vis_stim(n_trials, randomise_V, randomise_theta, filename)

if mod(n_trials,2)
    n_trials = n_trials+1;
    display('Number of trials has been increased by 1 to an even number in order to present equal number of ipsi/contra projections');
end

% Clear any previous visual stimulus
sca;
PsychDefaultSetup(2);

% Initatilise arduino
ard = arduino;

% Set keys to pay attention to during KbCheck (need to change if using on Mac)
scanlist = zeros(1,256);
scanlist(123) = 1; % F12

% Open screen window (this is the projector) and colour it blue 
screenid = 2;
[win2, winRect] = PsychImaging('OpenWindow', screenid, [0 0 1]);

% Antialiasing
Screen('BlendFunction', win2, GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

% Get the size of the screen in pixels and define centre
[screenXpixels, screenYpixels] = Screen('WindowSize', win2);
xCentre = screenXpixels / 2;
yCentre = screenYpixels / 2;

% Query the frame duration
ifi = Screen('GetFlipInterval', win2);

% Set the color of our looming stimuli to black
rectColor = [0 0 0];

%%
% Define the pixels per mm size. Dependent on resolution of projector/distance from screen
% This is manually calibrated by physically measuring a black square of known pixels on screen at known distance
% At 1920*1080 and 40 cm away, 7.1428 px per mm 
% At 1920*1080 and 26 cm away, 10 px per mm
% At 1280*800 and 40 cm away, 5 px per mm
perpx = 10;
baseRect = [0 0 perpx*3 perpx*3]; % square starts at 3 mm as per Kiran et al


% Define properties of the visual stim for N trials
% velocity = 11; % (L = 11, V = 11, L/V = 1 s)
% velocity = 27.5; % (L = 11, V = 27.5, L/V = 0.4 s)
half_L = 5.5;

% If randomise velocities, create list of same number of slow (V = 11) and fast (V = 27.5) velocities and randomise. 
if randomise_V == 1
    list_velocity = [11*ones(n_trials/2,1); 27.5*ones(n_trials/2,1)];
    list_velocity = list_velocity(randperm(n_trials));
end

% In my case, the projector is upside down (due to physical space) so these are inverted.
% Therefore, negative values are on the left of the fish, positive values
% on the right side of the fish
if randomise_theta == 1
    
    % 175 px offset = 45 deg offset when fish is centered in dish
    % 101 px offset = 30 deg offset when fish is centered in dish
    % 45 deg offset when fish is 8 mm from screen is (45/6.27) * 10 px
    % 30 deg offset when fish is 8 mm from screen is (30/6.27) * 10 px
    px_angle_offset = (60/6.27)*perpx;
    list_offset = [px_angle_offset*ones(n_trials/2,1); -px_angle_offset*ones(n_trials/2,1)];
    list_offset = list_offset(randperm(n_trials));
end

% Pause for 10s on blank blue screen prior to initiating trial
pause(10)

% Iterate through each trial
for i = 1:n_trials
    
    % Get velocity and x pixel offset for given trial
    velocity = list_velocity(i);
    x_offset = list_offset(i);
    y_offset = -150; % To centre stimulus on the screen along y on my setup (again manually calibrated)
    
    % Initalise looming stimulus
    centeredRect = CenterRectOnPointd(baseRect, xCentre+x_offset, yCentre+y_offset);
    currL = baseRect;
    loom_time = 0;

    %%
    % Populate background with a matrix of squares with colours [0 0 1] and [0 0 0.5]
    % number of squares for a given resolution
    % Screen is divided into squares of same size as original square
    n_squares = (screenXpixels/(perpx*3)) * (screenYpixels/(perpx*3)); 
    
    % Populate rects
    cellRects=ArrangeRects(n_squares/3, [0 0 perpx*30 perpx*30], winRect)';
    
    % Colours for background
    list_colours = [0 0 0.5; 0 0 1]; 
    bg_colours = datasample(list_colours, n_squares/3)';
    
    % Add squares to background, wait 20/5 seconds, then introduce looming stimuli for
    % 5 s before enlarging stim
    Screen('FillRect', win2, bg_colours, cellRects);
    Screen('Flip', win2);
       
    if i == 1
        pause(20);
    else
        pause(5);
    end
    
    % Write to arduino to signal inital presenation of stimuli
    % This allows us to sync visual stimulus presentation to electrophysiological recordings
    % (The arduino outputs to an input on the ephys rig)
    writePWMVoltage(ard,'D9', 2.9);
    Screen('FillRect', win2, bg_colours, cellRects);
    Screen('FillRect', win2, rectColor, centeredRect);
    Screen('Flip', win2);
    writePWMVoltage(ard,'D9', 0);
    
    % Wait another 10 s after visual stim offset
    pause(10);
    
    %%
    % Maximum priority level
    topPriorityLevel = MaxPriority(win2);
    Priority(topPriorityLevel);
    
    % Define voltage PWM for arduino dependent on stimuli (left/right and fast/slow)
    % Later on, this allows us to know properties of the visual stimulus from only one input
    if list_velocity(i) == 27.5
        if list_offset(i) < 0
            ard_v = 4.5;
        elseif list_offset(i) > 0
            ard_v = 4;
        end
    elseif list_velocity(i) == 11
        if list_offset(i) < 0
            ard_v = 3.5;
        elseif list_offset(i) > 0
            ard_v = 3;
        end
    end
    
     
    % Start timer for some readout of stimuli duration
    tic
    % write to arduino for onset of stimulus enlargement
    writePWMVoltage(ard,'D9', ard_v);
    % Loop the animation until a key is pressed    
    while ~PsychHID('KbCheck', [], scanlist)
        
        % Draw and flip to screen with background and centeredRect 
        Screen('FillRect', win2, bg_colours, cellRects);
        Screen('FillRect', win2, rectColor, centeredRect);
        Screen('Flip', win2);
        
        % Increment the time
        loom_time = loom_time + ifi;
        n_frame = round(loom_time/ifi);        
             
        if n_frame > 0
            % Perceived distance of stimulus relative to centre of dish
            perceived_dist(n_frame) = 50 - (velocity * loom_time);
            % Find half azimuthal angle from centre of dish
            half_theta(n_frame) = (atand(half_L / perceived_dist(n_frame)));
            % Find length of opposite leg (i.e size of stimulus on screen)
            half_length_curr(n_frame) = tand(half_theta(n_frame)) * 17.5; % 17.5 = r of dish
            % Here is time (for debugging sakes)
            time(n_frame) = loom_time;
            
            
            if n_frame > 1
                % Find difference between current frame and frame-1 for change in size of stim
                half_length_diff(n_frame) = half_length_curr(n_frame) - half_length_curr(n_frame-1);
                % Convert to pixels and double (since calculations above are for half azimuth)
                increment = half_length_diff(n_frame) * perpx * 2;
                % add to previous size
                currL = currL + [ 0 0 increment increment];
            else
                % Since it's first frame, no change in size; currL remains
                % same size. This else is redundant?
                half_length_diff = 0;
            end
        end
        
        % Update centeredRect with new currL
        centeredRect = CenterRectOnPointd(currL, xCentre+x_offset, yCentre+y_offset);
        if n_frame > 0
            % If stimuli occupies > 180 deg of screen, break and exit while loop
            if half_theta(n_frame) < 0
                break
            end
        end    
    end
    dur = toc;
    fprintf('duration = %6.2f.\n', dur);
    fprintf('ard voltage = %6.2f.\n', ard_v);
    writePWMVoltage(ard,'D9', 0);

    % Save info about the stimuli to datastruct ds

    ds(i).velocity = list_velocity(i);
    ds(i).L = half_L*2;
    ds(i).offset = list_offset(i);
    ds(i).duration = dur;
    ds(i).ard_v = ard_v;
    ds(i).time = time(1:end-1);
    ds(i).theta = half_theta(1:end-1)*2;
    ds(i).length = half_length_curr(1:end-1)*2;
    ds(i).diff = half_length_diff(1:end-1)*2;
    ds(i).perceived_dist = perceived_dist(1:end-1);
    ds(i).collision_time = -(perceived_dist(1:end-1) / list_velocity(i));
    
    
    clear time half_theta half_length_curr half_length_diff perceived_dist
    
end

save(strcat(filename, '.mat'), 'ds');

% Close screen and clear all variables
Screen('Close', win2);
%clear all
end