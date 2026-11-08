"""Deterministic, local source-edge cut for two authored A03 shoulder ornaments.

No model writes. Seeds cover pale and pink ornament roots, while the low torso,
arms, neck and horn outside the exact spatial ROI remain fixed sink faces.
"""
import sys,collections
import numpy as np
class Flow:
 def __init__(self,n):self.adj=[[]for _ in range(n)]
 def add(self,a,b,c):
  u=[b,c,len(self.adj[b])];vv=[a,0.,len(self.adj[a])];self.adj[a].append(u);self.adj[b].append(vv)
 def run(self,s,t):
  total=0
  while True:
   level=[-1]*len(self.adj);level[s]=0;que=collections.deque([s])
   while que:
    u=que.popleft()
    for vv,c,r in self.adj[u]:
     if c>1e-12 and level[vv]<0:level[vv]=level[u]+1;que.append(vv)
   if level[t]<0:break
   ptr=[0]*len(level)
   def dfs(u,amount):
    if u==t:return amount
    while ptr[u]<len(self.adj[u]):
     e=self.adj[u][ptr[u]];vv,c,r=e
     if c>1e-12 and level[vv]==level[u]+1:
      dd=dfs(vv,min(amount,c))
      if dd>1e-12:e[1]-=dd;self.adj[vv][r][1]+=dd;return dd
     ptr[u]+=1
    return 0.
   while True:
    pushed=dfs(s,1e9)
    if pushed<=1e-12:break
    total+=pushed
  reached=np.zeros(len(level),bool);reached[s]=True;que=collections.deque([s])
  while que:
   u=que.popleft()
   for vv,c,r in self.adj[u]:
    if c>1e-12 and not reached[vv]:reached[vv]=True;que.append(vv)
  return total,reached

def attachment_mask(v,f,oldmask,rgb):
 q=v[f].mean(1);w,iv=np.unique(v,axis=0,return_inverse=True);ff=iv[f]
 edges=np.sort(np.concatenate([ff[:,[0,1]],ff[:,[1,2]],ff[:,[2,0]]]),axis=1);fid=np.tile(np.arange(len(f)),3);order=np.lexsort(edges.T);edges=edges[order];fid=fid[order];bounds=np.r_[0,np.flatnonzero(np.any(edges[1:]!=edges[:-1],axis=1))+1,len(edges)]
 region=(((q[:,0]<-.105)&(q[:,2]>.0))|((q[:,0]>.195)&(q[:,2]<.10)))&(q[:,1]>.205)
 ids=np.flatnonzero(region);mapping=np.full(len(f),-1);mapping[ids]=np.arange(len(ids));s=len(ids);t=s+1;flow=Flow(t+1)
 pink=(rgb[:,0]>rgb[:,1]*1.9)&(rgb[:,2]>rgb[:,1]*1.9)&(rgb[:,0]>.20)&(rgb[:,2]>.22)
 seeds=region&((oldmask&(q[:,1]>.275))|(pink&(q[:,1]>.235)&(((q[:,0]<-.13)&(q[:,2]>.05))|((q[:,0]>.22)&(q[:,2]<.065)))))
 for i in np.flatnonzero(seeds):flow.add(s,int(mapping[i]),1e6)
 for start,stop in zip(bounds[:-1],bounds[1:]):
  faces=fid[start:stop]
  if not region[faces].any():continue
  edge=edges[start];length=float(np.linalg.norm(w[edge[0]]-w[edge[1]]))
  for i in range(len(faces)):
   for j in range(i+1,len(faces)):
    aa,bb=faces[[i,j]];ia,ib=int(mapping[aa]),int(mapping[bb])
    if ia>=0 and ib>=0:flow.add(ia,ib,length);flow.add(ib,ia,length)
    elif ia>=0:flow.add(ia,t,length)
    elif ib>=0:flow.add(ib,t,length)
 previous=sys.getrecursionlimit();sys.setrecursionlimit(max(previous,100000))
 try:cost,reached=flow.run(s,t)
 finally:sys.setrecursionlimit(previous)
 removed=np.zeros(len(f),bool);removed[ids[reached[:s]]]=True
 assert removed.sum()==14241
 return removed
