"""A04 reopened helmet: one consistent projection for triangulation/FEM/skull lift."""
import numpy as np
from remove_grifalon_gale_wind import triangulate


def conjugate_gradient(rows, cols, weights, diagonal, rhs):
    def multiply(x):
        return diagonal*x-np.bincount(rows, weights=weights*x[cols], minlength=len(rhs))
    x=np.zeros(len(rhs));r=rhs.copy();z=r/diagonal;p=z.copy();rz=np.dot(r,z)
    target=max(np.linalg.norm(rhs)*1e-11,1e-13)
    for _ in range(max(100,len(rhs)*3)):
        if np.linalg.norm(r)<target:break
        ap=multiply(p);den=np.dot(p,ap)
        assert den>0,'Crown Dirichlet matrix must be positive definite'
        step=rz/den;x+=step*p;r-=step*ap;z=r/diagonal;new_rz=np.dot(r,z)
        p=z+new_rz/max(rz,1e-300)*p;rz=new_rz
    assert np.linalg.norm(r)<target*10,'Crown FEM did not converge'
    return x


def crown_patch(boundary, bulge):
    """Keep every source boundary point; solve harmonic height + Poisson dome.

    The original nonconvex boundary is triangulated before refinement. Boundary
    edges never subdivide, so the retained source triangles need no edits.
    """
    fixednormal=np.array([-.16230731,1.,-.33119037]);fixednormal/=np.linalg.norm(fixednormal);fixedaxis=np.cross(fixednormal,[1,0,0]);fixedaxis/=np.linalg.norm(fixedaxis);fixedsecond=np.cross(fixednormal,fixedaxis)
    flat=np.column_stack([boundary@fixedaxis,boundary@fixedsecond,np.zeros(len(boundary))])
    try:tris,_=triangulate(flat)
    except ValueError:
        from remove_grifalon_gale_wind import crossings
        rng=np.random.default_rng(501);found=False
        for _ in range(12000):
            nn=np.array([rng.uniform(-.5,.3),1.,rng.uniform(-.6,.0)]);nn/=np.linalg.norm(nn);uu=np.cross(nn,[1,0,0]);uu/=np.linalg.norm(uu);vv=np.cross(nn,uu);fflat=np.column_stack([boundary@uu,boundary@vv,np.zeros(len(boundary))])
            # vectorized non-adjacent edge crossing test
            aa=fflat[:,:2];bb=np.roll(aa,-1,axis=0);i,j=np.triu_indices(len(aa),2);good=~((i==0)&(j==len(aa)-1));i,j=i[good],j[good]
            def cross2(a,b):return a[:,0]*b[:,1]-a[:,1]*b[:,0]
            cross=(cross2(bb[i]-aa[i],aa[j]-aa[i])*cross2(bb[i]-aa[i],bb[j]-aa[i]) < -1e-16)&(cross2(bb[j]-aa[j],aa[i]-aa[j])*cross2(bb[j]-aa[j],bb[i]-aa[j]) < -1e-16)
            if not cross.any():
                try:tris,_=triangulate(fflat)
                except ValueError:continue
                fixednormal,fixedaxis,fixedsecond=nn,uu,vv;found=True;break
        assert found,'No valid simple roof projection'
    vertices=boundary.astype(float).tolist();nb=len(boundary)
    protected={tuple(sorted((i,(i+1)%nb)))for i in range(nb)}
    for _ in range(5):
        p=np.asarray(vertices);edges=np.concatenate([tris[:,[0,1]],tris[:,[1,2]],tris[:,[2,0]]]);edges=np.unique(np.sort(edges,1),axis=0)
        chosen={tuple(e)for e in edges if tuple(e)not in protected and np.linalg.norm(p[e[0]]-p[e[1]])>.012}
        if not chosen:break
        mid={}
        for a,b in sorted(chosen):mid[(a,b)]=len(vertices);vertices.append(((p[a]+p[b])/2).tolist())
        out=[]
        for a,b,c in tris:
            ab=mid.get(tuple(sorted((a,b))));bc=mid.get(tuple(sorted((b,c))));ca=mid.get(tuple(sorted((c,a))))
            count=sum(x is not None for x in (ab,bc,ca))
            if count==0:out.append([a,b,c])
            elif count==3:out.extend([[a,ab,ca],[ab,b,bc],[ca,bc,c],[ab,bc,ca]])
            elif count==1:
                if ab is not None:out.extend([[a,ab,c],[ab,b,c]])
                elif bc is not None:out.extend([[b,bc,a],[bc,c,a]])
                else:out.extend([[c,ca,b],[ca,a,b]])
            elif ab is None:out.extend([[c,ca,bc],[a,b,ca],[ca,b,bc]])
            elif bc is None:out.extend([[a,ab,ca],[b,c,ab],[ab,c,ca]])
            else:out.extend([[b,bc,ab],[c,a,bc],[bc,a,ab]])
        tris=np.asarray(out,dtype=np.uint32)
    points=np.asarray(vertices);center=boundary.mean(0);_,_,basis=np.linalg.svd(boundary-center,False)
    # Boundary orientation determines the outward direction, including underside.
    normal=np.cross(boundary-center,np.roll(boundary,-1,axis=0)-center).sum(0)
    normal=fixednormal.copy()
    axis=fixedaxis.copy();second=fixedsecond.copy()
    q=np.column_stack([(points-center)@axis,(points-center)@second]);z=(points-center)@normal
    if bulge is not None:
        nt=len(points);rows=[];cols=[];ws=[];areas=np.zeros(nt)
        for a,b,c in tris:
            ids=[a,b,c];xy=q[ids];u2=xy[1]-xy[0];v2=xy[2]-xy[0];cross=abs(u2[0]*v2[1]-u2[1]*v2[0]);assert cross>1e-14
            areas[ids]+=cross/6
            for opposite in range(3):
                i,j=ids[(opposite+1)%3],ids[(opposite+2)%3]
                u=q[i]-q[ids[opposite]];v=q[j]-q[ids[opposite]];weight=np.dot(u,v)/cross/2
                rows.extend([i,j]);cols.extend([j,i]);ws.extend([weight,weight])
        rows=np.asarray(rows);cols=np.asarray(cols);ws=np.asarray(ws)
        diagonal=np.bincount(rows,weights=ws,minlength=nt)
        interior=rows>=nb;ii=interior&(cols>=nb);ib=interior&(cols<nb)
        rhs=np.bincount(rows[ib]-nb,weights=ws[ib]*z[cols[ib]],minlength=nt-nb)
        base=conjugate_gradient(rows[ii]-nb,cols[ii]-nb,ws[ii],diagonal[nb:],rhs)
        dome=conjugate_gradient(rows[ii]-nb,cols[ii]-nb,ws[ii],diagonal[nb:],areas[nb:])
        assert dome.max()>0
        z[nb:]=base+bulge*dome/dome.max()
        points=center+q[:,0,None]*axis+q[:,1,None]*second+z[:,None]*normal
        points[:nb]=boundary  # exact source seam, avoiding any projection rounding
    # Shape a rounded skull roof in a crossing-free fixed projection.
    boundary_q=q[:nb];distance=np.full(len(q),np.inf)
    for j in range(nb):
        aa,bb=boundary_q[j],boundary_q[(j+1)%nb];edge=bb-aa;t=np.clip((q-aa)@edge/max(edge@edge,1e-20),0,1);distance=np.minimum(distance,np.linalg.norm(q-aa-t[:,None]*edge,axis=1))
    mix=1-np.exp(-(distance/.004)**2)
    ellipse=1-((points[:,0]-.040)/.054)**2-((points[:,2]-.089)/.043)**2
    roof=.350+.047*np.sqrt(np.maximum(ellipse,0));shift=np.maximum(0,roof-points[:,1])*mix/normal[1]
    shift+=.006*(1-np.exp(-distance/.0007))*np.exp(-distance/.009)
    shift[:nb]=0;points+=shift[:,None]*normal
    face_n=np.cross(points[tris[:,1]]-points[tris[:,0]],points[tris[:,2]]-points[tris[:,0]])
    normals=np.zeros_like(points)
    for corner in range(3):np.add.at(normals,tris[:,corner],face_n)
    normals/=np.maximum(np.linalg.norm(normals,axis=1,keepdims=True),1e-12)
    donor=np.linalg.norm(points[:,None,:]-boundary[None,:,:],axis=2).argmin(1)
    donor[:nb]=np.arange(nb)
    assert np.isfinite(points).all() and np.isfinite(normals).all()
    return points.astype(np.float32),normals.astype(np.float32),tris,donor,{'boundary_vertices':nb,'vertices':len(points),'triangles':len(tris),'bulge':bulge,'outward_normal':normal.tolist(),'method':('fixed-boundary cotangent FEM harmonic height plus normalized Poisson dome' if bulge is not None else 'original safe underside triangulation refined without moving its surface')+'; interior edge target <=0.012'}
