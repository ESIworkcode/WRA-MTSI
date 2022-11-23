function [ImagingKernel,par]=SBL(B,L,varargin)
%==========================================================================
% Discriptions: this function is to compute the unknown source s.The model
%    is B=Ls+noise. 
% Input: L:   the leadfield matrix
%        B:   the observed data

%        varargin:%!!!!����'flags',0,'prune',[1 1e-6],'epsilon',1e-4, 'max_iter',150,'print',1,'nlf',1����������
%       flags:  choose which algorithm to compute the unknown s
%                      flags=0:  EM algorithm
%                      flags=1:  Mackay updatas
%                      flags=2:  Convexity_based approach
%                      flags=[3,p]: SMAP (MFOCUSS)
%      prune (1x2 vector):   whether prune the smallest gamma during iterations (0 or 1) and the prune threshold ( typically 1e-6)
%      epsilon:  stop condition (typically 1e-4)
%      max_iter: the largest numbers of iteration  
%      print :   whether print the iteration process
%      nlf   :   whether normalize the lead field matrix
          
% Output: ImagingKernel
%        gamma : estimated hyperparameters
%        evidence : cost funcitons

% Reference: David Wipf and Srikantan Nagarajan
%         A unified Bayesian framework for MEG/EEG source imaging. 2009

% data: 2012/8/30 (version 1.1)
%       2013/12/2 (version 1.2)
% Author: Liu Ke
%==========================================================================
 
% Dimension of the inverse problem
 nSource=size(L,2);                 % number of total sources
 [nSensor,nSnap]=size(B);           % number of sensors and time points    B������db*n
 % Default Control Parameters ���û�и���ʼֵ����ʹ��Ĭ��ֵ
epsilon        = 1e-6;        % threshold for stopping iteration. 
MAX_ITER       = 300;        % maximum iterations
print          = 1;           % show progress information
flags          = 2;           % iteration algorithm (0:EM; 1:Makay; 2:Convexity; 3: MFOCUSS)
prune          = [0 1e-6];    % whether prune the smallest gamma��һ��ֵ��ʾ�Ƿ�ɾ����С��gamma��0����1��,�ڶ���ֵ��ʾɾ����ֵ
NLFM           = 0;           % whether normalize the lead field matrix
beta           = 1;           % variance of sensor noise
Cov_n          = eye(nSensor);%db*db�ĵ�λ����
% get input argument values
if(mod(length(varargin),2)==1)
    error('Optional parameters should always go by pairs\n');
else
    for i=1:2:(length(varargin)-1)
        switch lower(varargin{i})%�Ѵ�д��ĸת����Сд��ĸ
            case 'nlf'
                NLFM = varargin{i+1}; 
            case 'epsilon'   
                epsilon = varargin{i+1}; 
            case 'print'    
                print = varargin{i+1}; 
            case 'max_iter'
                MAX_ITER = varargin{i+1}; 
            case 'cov_n'
                Cov_n = varargin{i+1}; 
            case 'flags'
                flags = varargin{i+1};  
            case 'prune'
                prune = varargin{i+1};  
            otherwise
                error(['Unrecognized parameter: ''' varargin{i} '''']);
        end
    end
end

fprintf('\nRunning Sparse Bayesian Learining...\n'); 
 %---------------initial states--------------%
 gamma = (ones(nSource,1) + randn(nSource,1)*1e-4)*nSensor/trace(L*L');% ������������ds*1��1�������ds*1�ľ��ȷֲ�������󣬳���ds,����L*L'��??????initial values of hyperparameters
 cost_old = 1;
 keep_list = (1:nSource)';%[1;2;3;4;....;ds]������
 evidence = zeros(MAX_ITER,1);%ÿ�ε����ĳɱ�����
 
%======================================%
%         Leadfield Matrix normalization
%=====================================%
if (NLFM)
% iG=sqrt(sum(L.^2,1))';
% iG(iG == 0) = min(iG(iG ~= 0));
% iG = spdiags((1 ./ iG) .^ 0.5, 0, length(iG), length(iG)) ;
% L =L* iG ;
% clear iG
    LfvW = (mean(L.^2,1)).^0.5;%��Lÿ��Ԫ��ƽ�����������ֵ����ÿ��Ԫ�ؿ�������ÿ��ֱ�����ֵ����,1*ds
    L = L.*kron(ones(nSensor,1),1./LfvW);%����������ones(nSensor,1)��db*1��1����1./LfvW��1*ds�ľ���kron(ones(nSensor,1),1./LfvW)��db*ds����
end
%=========================================================================%
%               iteration
%=========================================================================%
 for iter=1:MAX_ITER
% ******** Prune things as hyperparameters go to zero **********%����������Ϊ0ʱɾ��
if (prune(1))
    index = find(gamma > max(gamma)* prune(2));
    gamma = gamma(index);
    L = L(:,index);
    keep_list = keep_list(index);
    if (isempty(gamma))   
        break; 
    end
end
% ========== Update hyperparameters ===========%
Ns = numel(keep_list);%ds �ĸ���
Cov_b = beta*Cov_n + L.*repmat(gamma',nSensor,1)*L';%(16)gamma'��1*ds,��չ��db�У��в���չ��repmat(gamma',nSensor,1)����cov_s,db*ds,ע�⣬ǰ���ǵ��L.*cov_s,�����ǳ�*L'��cov_b��db*db
  
for k = 1:Ns%��1��ds��Դλ�õ���Ϣѭ��,Ȼ�����gama��1����gama��2����...,gama��ds����Ҳ���������gama������ds*1
                          
    M = gamma(k)*L(:,k)'/Cov_b;%��k��Դλ�õ�gama����L�������е�k�е�ת�ã���L�ĵ�k��Դλ�õ����д�������Ϣ                                                                         
    if (flags(1) == 0)
        %-------------EM algorithm---------------%
        gamma(k) = (norm(M*B,'fro'))^2/nSnap+gamma(k)-trace(M*L(:,k)*gamma(k));%(27)
     elseif (flags(1) == 1)
              % -----------MacKay updatas--------------%
           
        gamma(k) = (norm(M*B,'fro'))^2/(nSnap*trace(M*L(:,k))); %(29)                                                                                                                                                             
    elseif (flags(1) == 2)
        %--------Convexity_based approach--------%
        gamma(k) = gamma(k)*norm(L(:,k)'/Cov_b*B,'fro')/sqrt(nSnap*trace((L(:,k)'/Cov_b)*L(:,k)));%(30)
    elseif (flags(1) == 3)
        %------------S-MAP-----------------------%
        p=flags(2);
        gamma(k) = ((norm(M*B,'fro'))^2/nSnap)^((2-p)/2);
    end
end
%  beta = norm(beta*Cov_b\B,'fro')^2/(nSnap*beta*trace(inv(Cov_b)))

cost = trace(B*B'/Cov_b)+nSnap*log(det(Cov_b))+nSnap*nSensor*log(2*pi);%(18)���������������֣�������
cost = -0.5*cost;%����������
MSE = (cost-cost_old)/cost;%����������
cost_old = cost;
if (print)%չʾ����
    disp(['SBLiters: ',num2str(iter),'   num voxels: ',num2str(Ns),'  MSE: ',num2str(MSE)])%�����һ�ε����Ĵ�����dsδ֪Դ���������ɱ�����MSE
end
if (abs(MSE) < epsilon)  break; end%�ɱ�����Ҫ�㹻С����С�ڷ�ֵ�ˣ��Ϳ���ֹͣ
evidence(iter)=cost;
 end
%% compute ImagingKernel and s
evidence=evidence(1:iter-1,:);

% Cov = diag(gamma)-diag(gamma)*L'/(eye(nSensor)+L*diag(gamma)*L')*L*diag(gamma);
% temp = zeros(nSource,1);
% temp(keep_list) = diag(Cov);
% Cov = temp;

temp=zeros(nSource,nSensor);%ds*db
ImagingKernel = (repmat(gamma,1,nSensor).*L')/Cov_b;%��13��repmat(gamma,1,nSensor)��cov_s,ds*db,repmat(gamma,1,nSensor).*L'�ǵ�ˣ��õ�ds*db,ImagingKernel����ds*db

if (Ns>0)
    temp(keep_list,:) = ImagingKernel;% ��ImagingKernel��ֵ��temp�ĵ�1��ds�У�������
end
 ImagingKernel = temp;
 s=ImagingKernel*B;
 par.gamma = gamma;%��gama��ֵ��par.gama,��par�����һ���ṹ��
 par.evidence = evidence;
 par.beta = beta;
 par.keeplist = keep_list;
fprintf('\nSparse Bayesian Learining Finished!\n'); 

