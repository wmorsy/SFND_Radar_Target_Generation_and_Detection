clear all
close all
clc;

%% Radar Specifications
%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Frequency of operation = 77GHz
% Max Range = 200m
% Range Resolution = 1 m
% Max Velocity = 70 m/s
% Velocity resolution = 3 m/s
%%%%%%%%%%%%%%%%%%%%%%%%%%%
%speed of light = 3e8
C = 3e8;
Rmax = 200;
Dres = 1;
Vmax = 70;
Vres = 3;
%% User Defined Range and Velocity of target
% define the target's initial position and velocity. Note : Velocity
% remains contant
Ro = 110; % max 200m
Vo = -20; % [-70:70]

%% FMCW Waveform Generation

%Design the FMCW waveform by giving the specs of each of its parameters.
% Calculate the Bandwidth (B), Chirp Time (Tchirp) and Slope (slope) of the FMCW
% chirp using the requirements above.

% The sweep bandwidth can be determined according to the range resolution
Bs = C / (2 * Dres);

% The sweep time can be computed based on the time needed for the signal to
% travel the unambiguous maximum range. In general, for an FMCW radar system,
% the sweep time should be at least 5 to 6 times the round trip time
Tchirp = 5.5 * 2 * Rmax/C;

% The sweep slope is calculated using both sweep bandwidth and sweep time.
A = Bs/Tchirp;
disp(A);

%Operating carrier frequency of Radar
Fc= 77e9;             %carrier freq


%The number of chirps in one sequence. Its ideal to have 2^ value for the ease of running the FFT
%for Doppler Estimation.
Nd=128;                   % #of doppler cells OR #of sent periods % number of chirps

%The number of samples on each chirp.
Nr=1024;                  %for length of time OR # of range cells

% Timestamp for running the displacement scenario for every sample on each
% chirp
t=linspace(0,Nd*Tchirp,Nr*Nd); %total time for samples


%Creating the vectors for Tx, Rx and Mix based on the total samples input.
Tx=zeros(1,length(t)); %transmitted signal
Rx=zeros(1,length(t)); %received signal
Mix = zeros(1,length(t)); %beat signal

%Similar vectors for range_covered and time delay.
r_t=zeros(1,length(t));
td=zeros(1,length(t));


%% Signal generation and Moving Target simulation
% Running the radar scenario over the time.

for i=1:length(t)

    %For each time stamp update the Range of the Target for constant velocity.
    r_t(i) = Ro + Vo*t(i);

    %For each time sample we need update the transmitted and
    %received signal.
    t_d = 2 * r_t(i) / C;
    Tx(i) = cos(2*pi*(Fc*t(i)+A*t(i)^2/2));
    Rx(i) = cos(2*pi*(Fc*(t(i)-t_d)+A*(t(i)-t_d)^2/2));

    %Now by mixing the Transmit and Receive generate the beat signal
    %This is done by element wise matrix multiplication of Transmit and
    %Receiver Signal
    Mix(i) = Tx(i)*Rx(i);

end

%% RANGE MEASUREMENT

%reshape the vector into Nr*Nd array. Nr and Nd here would also define the size of
%Range and Doppler FFT respectively.
Mix=reshape(Mix,[Nr,Nd]);

%run the FFT on the beat signal along the range bins dimension (Nr) and
%normalize.
signal_fft = fft(Mix)./Nr;

% Take the absolute value of FFT output
signal_fft = abs(signal_fft); % Amplitude of Normalied signal

% Output of FFT is double sided signal, but we are interested in only one side of the spectrum.
% Hence we throw out half of the samples.
signal_fft = signal_fft(1:Nr/2+1);

%plotting the range
figure ('Name','Range from First FFT')
subplot(2,1,1)
% plot FFT output
axis ([0 200 0 1]);
plot(signal_fft);
title('Range FFT output for target at 110m');


%% RANGE DOPPLER RESPONSE
% The 2D FFT implementation is already provided here. This will run a 2DFFT
% on the mixed signal (beat signal) output and generate a range doppler
% map.You will implement CFAR on the generated RDM


% Range Doppler Map Generation.

% The output of the 2D FFT is an image that has reponse in the range and
% doppler FFT bins. So, it is important to convert the axis from bin sizes
% to range and doppler based on their Max values.
Mix=reshape(Mix,[Nr,Nd]);

% 2D FFT using the FFT size for both dimensions.
sig_fft2 = fft2(Mix,Nr,Nd);

% Taking just one side of signal from Range dimension.
sig_fft2 = sig_fft2(1:Nr/2,1:Nd);
sig_fft2 = fftshift (sig_fft2);
RDM = abs(sig_fft2);
RDM = 10*log10(RDM) ;

%use the surf function to plot the output of 2DFFT and to show axis in both
%dimensions
doppler_axis = linspace(-100,100,Nd);
range_axis = linspace(-200,200,Nr/2)*((Nr/2)/400);
figure,surf(doppler_axis,range_axis,RDM);
title('Range Doppler Map - 2D FFT output');

%% CFAR implementation

%Slide Window through the complete Range Doppler Map

%Select the number of Training Cells in both the dimensions.
Tr=12;
Td=12;

%Select the number of Guard Cells in both dimensions around the Cell under
%test (CUT) for accurate estimation
Gr=4;
Gd=4;

% offset the threshold by SNR value in dB
offset=15;

%Create a vector to store noise_level for each iteration on training cells
noise_level = zeros(1,1);

%design a loop such that it slides the CUT across range doppler map by
%giving margins at the edges for Training and Guard Cells.
%For every iteration sum the signal level within all the training
%cells. To sum convert the value from logarithmic to linear using db2pow
%function. Average the summed values for all of the training
%cells used. After averaging convert it back to logarithimic using pow2db.
%Further add the offset to it to determine the threshold. Next, compare the
%signal under CUT with this threshold. If the CUT level > threshold assign
%it a value of 1, else equate it to 0.
grid_size = (2*Tr+2*Gr+1) * (2*Td+2*Gd+1);
training_size = grid_size - (2*Gr+1)*(2*Gd+1);

signal_cfar = zeros(size(RDM));

for i = Tr+Gr+1:Nr/2-(Gr+Tr)
    for j = Td+Gd+1:Nd-(Gd+Td)
   % Use RDM[x,y] as the matrix from the output of 2D FFT for implementing
   % CFAR
        % get the training cells and set CUT and guard cells to 0
        T = RDM((i-Tr-Gr:i+Tr+Gr),(j-Td-Gd:j+Td+Gd));
        T((i-Gr:i+Gr),(j-Gd:j+Gd)) = 0;
        % convert the value from logarithmic to linear and get the mean
        noise_level = mean(db2pow(T));
        % convert back to logarithmic
        noise_level = pow2db(noise_level);
        % get the threshold value by adding the offset
        threshold = noise_level + offset;
        signal_cut = RDM(i,j);
        if (signal_cut>threshold)
            signal_cfar(i,j) = 1;
        end
    end
end

% The process above will generate a thresholded block, which is smaller
%than the Range Doppler Map as the CUT cannot be located at the edges of
%matrix. Hence,few cells will not be thresholded. To keep the map size same
% set those values to 0.

% signal_cfar was already initalized to 0

%display the CFAR output using the Surf function like we did for Range
%Doppler Response output.
figure,surf(doppler_axis,range_axis,signal_cfar);
colorbar;



