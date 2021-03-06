function [TF,gap_dt,gap_dt_s] = stochasticTF_RL(nodes,links,destinations,simTT,cvn_up,dt,totT,rc_dt,rc_agg,mu,betas,structures,display)
% This file is part of the ITSCrealab (see https://gitlab.mech.kuleuven.be/ITSCreaLab)
% developed by the KULeuven. 
%
% Copyright (C) 2016  Himpe Willem, Leuven, Belgium
%
% This program is free software: you can redistribute it and/or modify
% it under the terms of the GNU General Public License as published by
% the Free Software Foundation, either version 3 of the License, or
% any later version.
% 
% This program is distributed in the hope that it will be useful,
% but WITHOUT ANY WARRANTY; without even the implied warranty of
% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
% GNU General Public License for more details.
% 
% You should have received a copy of the GNU General Public License
% along with this program.  If not, see <http://www.gnu.org/licenses/>.
%
% More information at: http://www.mech.kuleuven.be/en/cib/traffic/downloads
% or contact: ITSCreaLab {@} kuleuven.be


totDest = length(destinations);
totNodes = length(nodes.id);
totLinks = length(links.id);
strN = links.fromNode;
endN = links.toNode;

if isempty(cvn_up)
    cvn_up=zeros(totLinks,totT+1,totDest);
end

updateTF = num2cell(ones(size(nodes.id,1),totT,totDest));
timeSteps = dt*[0:1:totT];
timeRC = rc_dt*[0:1:totT];
timeRC(timeRC>timeSteps(end))=[];

gap = zeros(totLinks,totT+1);
gap_dt = 0;
gap_s = zeros(totLinks,totT+1);
gap_dt_s = 0;
act_t = false(1,totT+1);
gVeh = floor(rc_dt/dt);


switch rc_agg
    case 'first'
        timeVeh = 0;
    case 'middle'
        timeVeh = rc_dt/2;
    case 'last'
        timeVeh = rc_dt;
    case 'Null'
        for d_index=1:totDest
            arr_map_d(d_index);
        end
        TF=[];
        return;
    case 'inst'
        for d_index=1:totDest
            d=destinations(d_index);
            netCostMatrix=sparse(endN,strN,simTT(:,1),totNodes,totNodes);
            [parent, ~] = dijkstra(netCostMatrix, d);
            for n=1:totNodes
                incomingLinks = find(endN==n);
                outgoingLinks = find(strN==n);
                TF{n,1,d_index}=zeros(max(1,length(incomingLinks)),length(outgoingLinks));
                TF{n,1,d_index}(:,endN(outgoingLinks)==parent(n))=1;
            end
        end
        gap = [];
        return;
        
end
tVeh = floor(timeVeh/dt);
fracVeh = timeVeh/dt-tVeh;

for d_index=1:totDest
    if(display)
        disp('destination');
        disp(d_index);
    end
    %use the arrival map order to compute the maximum perceived utility
    util_map = max_perc_util_d(d_index);
    
    %compute update of the turning fractions based on the utiliy values
    for n=1:totNodes
        next_rc=1;
        incomingLinks = find(endN==n);
        outgoingLinks = find(strN==n);
        
        if length(outgoingLinks)<=1
            %no update is required for a non divergent node
            for t=1:totT
                TF{n,t,d_index}=ones(max(1,length(incomingLinks)),max(1,length(outgoingLinks)));
            end            
        else
            for t=1:totT   
                %update all turning fractions
                %interval by same value
                if timeSteps(t)>=timeRC(min(length(timeRC),next_rc))
                    next_rc = next_rc+1;
                    act_t(min(totT+1,t+tVeh))=true;

                    %compute the turn probabilities

                    P=zeros(length(incomingLinks),length(outgoingLinks));
                    
                    for l=1:length(incomingLinks)
                        l_in=incomingLinks(l);
                        for i=1:length(outgoingLinks)
                            l_out=outgoingLinks(i);
                            if isinf(util_map(l_out,end))
                                continue;
                            end                            
                            
                            time=timeSteps(min(totT+1,t+tVeh))+simTT(l_out,min(totT+1,t+tVeh));
                            
                            %val=interpoleren+TT+penalties                    
                            
                            %interpolatie                                                  
                            if time>=timeSteps(end)
                                val =util_map(l_out,end);
                            else
                                t1 = min(totT+1,max(t+tVeh+1,1+floor(time/dt)));
                                t2 = min(totT+1,t1+1);
                                
                                val = util_map(l_out,t1)+max(0,(1+time/dt-t1))*(util_map(l_out,t2)-util_map(l_out,t1));
                                
                                if(1+round(time/dt)-t)<1
                                    disp('<<<To large timestep>>>');
                                end
                            end
                            
                            %utility                  
                            val = val + utilityfunction(simTT(l_out,t),l_in,l_out,t);
                            
                            P(l,i)=exp(mu*val); %not normalized
                        end
                    end
                end
                %updating of the turning fractions
                TF{n,t,d_index}=zeros(max(1,length(incomingLinks)),length(outgoingLinks));
                if sum(P)==0
                    continue;
                end
                TF{n,t,d_index}=P./repmat(sum(P,2),1,length(outgoingLinks));
            end
        end
    end
    
    if nargout>1
        arr_map_d(d_index);
        gap_dt=gap_dt+sum(sum(gap(:,2:end).*diff(cvn_up(:,:,d_index),1,2)));
        gap_dt_s=gap_dt_s+sum(sum(gap_s(:,2:end).*diff(cvn_up(:,:,d_index),1,2)));
    else
        gap = inf;
        gap_s = inf;
    end  
end
% fprintf('\n');

%Nested function used for finding the maximum perceived utility
    function [util_map] = max_perc_util_d(d_index)
        if(display)
            disp('<begin mpu');
        end
        d=destinations(d_index);
        util_map = zeros(totLinks,totT+1);
        %first do the last time slice
        
        %here static part of Recursive Logit

        %compute the deterministic part
        TT=(repmat(endN,1,totLinks)==repmat(strN',totLinks,1)).*repmat(simTT(:,end)',totLinks,1);
        v = utilityfunction(TT);
        %compute M (connectivity & travel time)
        M = exp(mu*v).*(TT>0);
        %compute b (destinations)
        b=zeros(totLinks,1);
        b(endN==d)=1;
        %compute z (exponent of value function)
        z = (eye(length(b)) -M)\b;
        if(display)
            disp('<z found');
        end
        %compute utility map
        util_map(:,totT+1)=1/mu*log(z);
        
        if(max(max(z))>1)
            error('utiliteiten groter dan 0')
        end
        
        %next do the others in upwind order
        for t=totT:-1:1
            if(display)
                if(mod(t,500)==0)
                    disp('<<mpu');
                    disp(t);
                end
            end
            for l_in=1:totLinks
                if any(endN(l_in)==destinations)
                    if endN(l_in)~=d
                        util_map(l_in,t)=-inf;
                    else
                        util_map(l_in,t)=0;
                    end
                    continue;
                end
                outgoingLinks = find(strN==endN(l_in));
                for l_out=outgoingLinks'
                    if isinf(util_map(l_out,end))
                        continue;
                    end
                    time=timeSteps(t)+simTT(l_out,t);
                    
                    %val=interpoleren+TT+penalties                    
                    %interpolatie
                    if time>=timeSteps(end)
                        val = util_map(l_out,end);
                    else
                        t1 = min(totT+1,max(t+1,1+floor(time/dt)));
                        t2 = min(totT+1,t1+1);  
                        
                        val = util_map(l_out,t1)+max(0,(1+time/dt-t1))*(util_map(l_out,t2)-util_map(l_out,t1)); % 1+time/dt-t niet lager dan 1 hier
                        %als lager dan 1, dan zou het moeten interpoleren
                        %met waarde uit zelfde tijdslaag
                        if (1+round(time/dt)-t)<1
                            disp('<<<To large timestep MPU>>>');
                        end
                    end
                    
                    %utility                  
                    val = val + utilityfunction(simTT(l_out,t),l_in,l_out,t);
                                        
                    util_map(l_in,t)=util_map(l_in,t)+exp(mu*val);
                end
                util_map(l_in,t) = 1/mu*log(util_map(l_in,t));
            end
        end
        if(display)
            disp('<end mpu');
        end
    end

    function utility=utilityfunction(TT,l_in,l_out,t)
        utility=-TT;
        for key=keys(betas)
            beta=betas(char(key));
            structure=structures(char(key));
            if not(isscalar(TT))
                utility=utility+beta*structure;
            else
                if ndims(structure)==3
                    utility=utility+beta*structure(l_in,l_out,t);
                else
                    utility=utility+beta*structure(l_in,l_out);
                end
            end
        end
    end

%Nested function used for finding the destination based arrival map
    function [arr_map,parent] = arr_map_d(d_index)
        d=destinations(d_index);
        netCostMatrix=sparse(endN,strN,simTT(:,end),totNodes,totNodes);
        [par, dist] = dijkstra(netCostMatrix, d);
        parent = zeros(totNodes,totT+1);
        parent(:,totT+1) = par;
        arr_map = zeros(totNodes,totT+1);
        arr_map(:,totT+1)=dist+dt*totT;
        for t=totT+1:-1:1
            for n=1:totNodes
                if any(n==destinations)
                    if n~=d
                        arr_map(n,t)=inf;
                    else
                        arr_map(n,t)=(t-1)*dt;
                    end
                    continue;
                end
                outgoingLinks = find(strN==n);
                arr = inf;
                min_phi = inf;
                for l=outgoingLinks'
                    time=timeSteps(t)+simTT(l,t);
                    if time>=timeSteps(end)
                        val=time-dt*totT+arr_map(endN(l),end);
                    else
                        t1 = min(totT+1,max(t+1,1+floor(time/dt)));
                        t2 = min(totT+1,t1+1);
                        val = arr_map(endN(l),t1,:)+max(0,(1+time/dt-t1))*(arr_map(endN(l),t2,:)-arr_map(endN(l),t1,:));
                    end
                    if cvn_up(l,t,d_index)-cvn_up(l,max(t-1,1),d_index)>0
                        gap(l,t) = gap(l,t) + val;
                        phi = 1/mu*log(cvn_up(l,t,d_index)-cvn_up(l,max(t-1,1),d_index))+val-(t-1)*dt;
                        gap_s(l,t) = phi;
                        if phi<=min_phi
                            min_phi=phi;
                        end
                    end
                    if val<=arr
                        arr=val;
                        parent(n,t) = endN(l);
                    end
                end
                for l=outgoingLinks'
                    if cvn_up(l,t,d_index)-cvn_up(l,max(t-1,1),d_index)>0
                        gap(l,t) = gap(l,t) - arr;
                        gap_s(l,t) = gap_s(l,t)-min_phi;
                    end
                end
                arr_map(n,t)=arr;
            end
        end
    end

end