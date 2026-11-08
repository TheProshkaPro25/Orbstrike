"""Boundary-preserving smooth crown patch for A04; NumPy-only local FEM solve."""
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
    tris,_=triangulate(boundary);vertices=boundary.astype(float).tolist();nb=len(boundary)
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
    normal/=np.linalg.norm(normal)
    axis=basis[0];second=np.cross(normal,axis);second/=np.linalg.norm(second)
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
    face_n=np.cross(points[tris[:,1]]-points[tris[:,0]],points[tris[:,2]]-points[tris[:,0]])
    normals=np.zeros_like(points)
    for corner in range(3):np.add.at(normals,tris[:,corner],face_n)
    normals/=np.maximum(np.linalg.norm(normals,axis=1,keepdims=True),1e-12)
    donor=np.linalg.norm(points[:,None,:]-boundary[None,:,:],axis=2).argmin(1)
    donor[:nb]=np.arange(nb)
    assert np.isfinite(points).all() and np.isfinite(normals).all()
    return points.astype(np.float32),normals.astype(np.float32),tris,donor,{'boundary_vertices':nb,'vertices':len(points),'triangles':len(tris),'bulge':bulge,'outward_normal':normal.tolist(),'method':('fixed-boundary cotangent FEM harmonic height plus normalized Poisson dome' if bulge is not None else 'original safe underside triangulation refined without moving its surface')+'; interior edge target <=0.012'}


def smooth_collar(arrays, faces, inverse, loop, radius=.008, max_shift=.003):
    """Smooth the cut seam and a bounded geodesic strip; preserve UV/skin/rig."""
    import heapq
    original=arrays['POSITION'].copy();old_normals=arrays['NORMAL'].copy()
    count=int(inverse.max())+1;points=np.zeros((count,3));points[inverse]=original
    boundary=points[loop];lengths=np.linalg.norm(np.roll(boundary,-1,axis=0)-boundary,axis=1)
    arc=np.r_[0,np.cumsum(lengths)];parameter=arc[:-1]/arc[-1]
    grid=np.arange(256)/256
    samples=np.column_stack([np.interp(grid,arc/arc[-1],np.r_[boundary[:,j],boundary[0,j]])for j in range(3)])
    spectrum=np.fft.rfft(samples,axis=0);frequencies=np.arange(len(spectrum));spectrum*=np.exp(-(frequencies/9)**4)[:,None]
    smooth=np.fft.irfft(spectrum,n=256,axis=0)
    target=np.column_stack([np.interp(parameter,np.r_[grid,1],np.r_[smooth[:,j],smooth[0,j]])for j in range(3)])
    shifts=target-boundary;norm=np.linalg.norm(shifts,axis=1)
    shifts*=np.minimum(1,max_shift/np.maximum(norm,1e-12))[:,None]
    edges=np.concatenate([inverse[faces[:,[0,1]]],inverse[faces[:,[1,2]]],inverse[faces[:,[2,0]]]])
    edges=np.unique(np.sort(edges,axis=1),axis=0);adj={}
    for a,b in edges:
        distance=float(np.linalg.norm(points[a]-points[b]))
        adj.setdefault(int(a),[]).append((int(b),distance));adj.setdefault(int(b),[]).append((int(a),distance))
    distances=np.full(count,np.inf);donors=np.full(count,-1,int);queue=[]
    for i,vertex in enumerate(loop):distances[vertex]=0;donors[vertex]=i;heapq.heappush(queue,(0,int(vertex)))
    while queue:
        distance,vertex=heapq.heappop(queue)
        if distance!=distances[vertex]:continue
        for other,weight in adj.get(vertex,[]):
            candidate=distance+weight
            if candidate<radius and candidate<distances[other]:
                distances[other]=candidate;donors[other]=donors[vertex];heapq.heappush(queue,(candidate,other))
    active=np.flatnonzero(distances<radius);t=np.clip(1-distances[active]/radius,0,1);blend=t*t*(3-2*t)
    delta=np.zeros_like(points);delta[active]=shifts[donors[active]]*blend[:,None]
    # Bound the deformation of every retained collar triangle, including slivers.
    old_tri=original[faces];old_cross=np.cross(old_tri[:,1]-old_tri[:,0],old_tri[:,2]-old_tri[:,0]);old_area=np.linalg.norm(old_cross,axis=1)
    face_weld=inverse[faces];affected=np.isin(face_weld,active).any(1);scales=np.ones(count)
    for _ in range(40):
        positions=original+(delta*scales[:,None])[inverse]
        new_tri=positions[faces];new_cross=np.cross(new_tri[:,1]-new_tri[:,0],new_tri[:,2]-new_tri[:,0]);new_area=np.linalg.norm(new_cross,axis=1)
        ratio=new_area/np.maximum(old_area,1e-20)
        cosine=np.einsum('ij,ij->i',old_cross,new_cross)/np.maximum(old_area*new_area,1e-20)
        bad=affected&((ratio<.35)|(ratio>2.5)|(cosine<.5))
        if not bad.any():break
        scales[np.unique(face_weld[bad])]*=.65
    assert not bad.any(),'Collar deformation limits did not converge'
    ids=np.flatnonzero(np.linalg.norm(positions-original,axis=1)>1e-12)
    arrays['POSITION']=positions.astype(original.dtype)
    # Rotate authored normals by the local geometric normal change.
    def geometric(v):
        triangles=v[faces];fn=np.cross(triangles[:,1]-triangles[:,0],triangles[:,2]-triangles[:,0]);normals=np.zeros_like(points)
        for j in range(3):np.add.at(normals,inverse[faces[:,j]],fn)
        normals/=np.maximum(np.linalg.norm(normals,axis=1,keepdims=True),1e-12)
        return normals
    before=geometric(original);after=geometric(positions);a=before[inverse[ids]];b=after[inverse[ids]]
    axis=np.cross(a,b);sin=np.linalg.norm(axis,axis=1);cos=np.einsum('ij,ij->i',a,b);axis/=np.maximum(sin[:,None],1e-12)
    n=old_normals[ids];rotated=n*cos[:,None]+np.cross(axis,n)*sin[:,None]+axis*np.einsum('ij,ij->i',axis,n)[:,None]*(1-cos[:,None])
    rotated[sin<1e-10]=n[sin<1e-10];rotated/=np.maximum(np.linalg.norm(rotated,axis=1,keepdims=True),1e-12)
    arrays['NORMAL']=old_normals.copy();arrays['NORMAL'][ids]=rotated.astype(old_normals.dtype)
    return {'source_vertex_ids':ids.tolist(),'source_welded_vertex_ids':active.tolist(),'geodesic_radius':radius,'max_displacement_limit':max_shift,'max_actual_displacement':float(np.linalg.norm(positions-original,axis=1).max()),'position_delta_l2':float(np.linalg.norm(positions-original)),'retained_triangle_min_area_ratio':float(ratio[affected].min()),'retained_triangle_max_area_ratio':float(ratio[affected].max()),'retained_triangle_min_normal_cosine':float(cosine[affected].min()),'method':'periodic arc-length Fourier seam fairing; bounded geodesic smoothstep collar; all UV copies; authored normal rotation only'}
