function frames=phase3_afc_frames(wave,nbuf)
%PHASE3_AFC_FRAMES Prebuild stereo frames; pad only the complete trial's tail.
validateattributes(nbuf,{'numeric'},{'scalar','integer','positive','finite'});
wave=wave(:);
n=ceil(numel(wave)/nbuf)*nbuf;
stereo=zeros(n,2); stereo(1:numel(wave),1)=wave;
frames=permute(reshape(stereo,nbuf,[],2),[1 3 2]);
end
