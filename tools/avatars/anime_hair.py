"""Three original anime haircuts made from overlapping sculpted wedges.
Wide roots blend into a continuous cap; asymmetric tips produce a drawn silhouette.
"""
import math
from mathutils import Vector
from anime_head import mesh_object,material

def create_anime_hair(human,rig):
    objects=[]
    for style in range(3):
        verts=[];faces=[];uv=[]
        center=Vector((0,.004,1.607));rx=.143;ry=.133;rz=.150
        n=64;rows=24
        for row in range(rows+1):
            for j in range(n):
                theta=j/n*math.tau;front=(1+math.cos(theta))*.5
                end=2.22-.96*front**4
                phi=.003+(end-.003)*row/rows
                verts.append(tuple(center+Vector((rx*math.sin(phi)*math.sin(theta),-ry*math.sin(phi)*math.cos(theta),rz*math.cos(phi)))))
                uv.append((j/n,row/rows))
        for row in range(rows):
            for j in range(n):
                a=row*n+j;b=row*n+(j+1)%n;faces.append((a+n,b+n,b,a))
        def lock(points,width,depth=.016):
            pts=[Vector(p) for p in points];start=len(verts);steps=18
            # A low convex wedge, not an elliptical leaf. Separate seam vertices
            # give the long sculpted plane a distinct highlight.
            section=[(-1,0),(-.55,.58),(0,1),(.52,.63),(1,0),(.5,-.18),(0,-.23),(-.5,-.18)]
            for k in range(steps+1):
                t=k/steps;u=1-t
                c=u**3*pts[0]+3*u*u*t*pts[1]+3*u*t*t*pts[2]+t**3*pts[3]
                tangent=(3*u*u*(pts[1]-pts[0])+6*u*t*(pts[2]-pts[1])+3*t*t*(pts[3]-pts[2])).normalized()
                outward=Vector((0,-1,0));across=outward.cross(tangent).normalized()
                root=min(1,t/.22);root=root*root*(3-2*root)
                taper=max(.0007,(1-t)**1.12*root)
                for j,(a,b) in enumerate(section):
                    verts.append(tuple(c+across*(a*width*taper)+outward*(b*depth*taper)))
                    uv.append(((a+1)/2,t))
            for k in range(steps):
                for j in range(8):
                    a=start+k*8+j;b=start+k*8+(j+1)%8;faces.append((a,b,b+8,a+8))
            faces.append(tuple(start+j for j in reversed(range(8))))
            faces.append(tuple(start+steps*8+j for j in range(8)))
        if style==0:
            # Connected swept crown; the roots overlap the skull and each other.
            crowns=[([(-.08,.015,1.65),(-.17,.015,1.72),(-.19,.012,1.72),(-.206,.01,1.71)],.075),
                    ([(-.055,.025,1.69),(-.13,.025,1.78),(-.17,.025,1.79),(-.192,.025,1.78)],.078),
                    ([(0,.04,1.71),(-.055,.04,1.81),(-.07,.04,1.85),(-.036,.04,1.87)],.083),
                    ([(.025,.03,1.71),(.035,.03,1.79),(.10,.03,1.82),(.148,.03,1.79)],.082),
                    ([(.07,.016,1.69),(.14,.016,1.75),(.18,.016,1.75),(.212,.016,1.76)],.073),
                    ([(.10,.02,1.64),(.15,.02,1.68),(.18,.02,1.68),(.208,.02,1.66)],.065)]
            for ps,w in crowns:
                tip=Vector(ps[3]);direction=(tip-Vector(ps[0])).normalized()
                ps[3]=tuple(tip+direction*.024)
                lock(ps,w,.021)
            bangs=[([(-.025,-.065,1.742),(-.08,-.145,1.716),(-.12,-.147,1.64),(-.139,-.095,1.527)],.052),
                   ([(.01,-.082,1.745),(-.037,-.145,1.70),(-.06,-.156,1.64),(-.022,-.147,1.586)],.060),
                   ([(.05,-.065,1.735),(.035,-.146,1.685),(.018,-.153,1.609),(.023,-.145,1.534)],.042),
                   ([(.09,-.041,1.708),(.14,-.111,1.66),(.133,-.124,1.605),(.111,-.103,1.535)],.046)]
        elif style==1:
            # Parted fringe with gathered hair at the nape.
            bangs=[([(-.014,-.075,1.747),(-.093,-.14,1.72),(-.151,-.10,1.61),(-.125,-.077,1.48)],.055),
                   ([(.008,-.073,1.749),(.064,-.145,1.71),(.109,-.137,1.64),(.089,-.11,1.54)],.055),
                   ([(.07,-.04,1.726),(.14,-.08,1.68),(.157,-.065,1.57),(.142,-.037,1.48)],.047)]
            for x in [-.035,.012,.05]:
                lock([(x,.095,1.67),(x+.015,.22,1.65),(x+.04,.23,1.47),(x+.025,.18,1.34)],.055,.035)
        else:
            # Short side sweep, an exposed brow, asymmetry instead of a smaller cap.
            bangs=[([(-.06,-.055,1.731),(-.05,-.14,1.722),(.05,-.158,1.655),(.107,-.132,1.59)],.065),
                   ([(-.09,-.05,1.71),(-.075,-.145,1.69),(.015,-.16,1.632),(.055,-.145,1.605)],.047),
                   ([(.075,-.02,1.7),(.133,-.08,1.67),(.154,-.078,1.62),(.132,-.06,1.55)],.049)]
            lock([(-.05,.025,1.71),(-.04,.025,1.77),(.05,.025,1.79),(.107,.025,1.76)],.085,.022)
        for points,width in bangs:lock(points,width,.015)
        for side in [-1,1]:
            lock([(side*.112,-.027,1.64),(side*.153,-.055,1.59),(side*.147,-.06,1.52),(side*.125,-.041,1.468)],.030,.013)
            if style==0:
                for i in range(2):
                    z=1.60-i*.059
                    lock([(side*.10,.05,z+.04),(side*.155,.03,z+.01),(side*.166,.016,z-.005),(side*.173,.01,z-.025)],.045,.021)
        obj=mesh_object('Hair%d'%style,verts,faces,rig,material('Hair',(.17,.075,.035)),uv)
        objects.append(obj)
    return objects
