Shader "Unlit/ScreenSpaceQuadPathTrace"
{
	Properties
	{
		
	}
	SubShader
	{
		Tags {"Queue"="Transparent" "IgnoreProjector"="True""RenderType"="Opaque" }
	

		Pass
		{
			ZWrite Off

			ZTest Off
			//cull Front

			Blend SrcAlpha OneMinusSrcAlpha //alpha blending
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			#pragma target 5.0

			#include "UnityCG.cginc"
			#define PI 3.14159265359

			#define DIFFUSE 0
			#define MIRROR	1
			#define GLASS	2

			#define SPHERE	0
			#define BOX		1

			//Uniform参数：Uniform是用来限制一个变量的初始值的来源，
			//当声明一个变量为Uniform类型的时候，
			//表示这个变量的初始值来自于外部的其他环境。
			uniform sampler2D _MainTex;

			uniform int MAX_DEPTH;
			uniform int SAMPLES;
			uniform int TotalFrames;
			uniform float2 Resolution;

			float seed=0;
			float rand(){return frac(sin(seed++)*43758.5453123);}

			uniform float4x4 FrustumCorners;

			struct v2f
			{
				float4 pos:SV_POSITION;
				float2 uv:TEXCOORD0;
				float3 view_dir:TEXCOORD1;
			};
			v2f vert(appdata_base v)
			{
				v2f OUT;
				OUT.pos=UnityObjectToClipPos(v.vertex);
				OUT.uv=v.texcoord;
				//interpolated from frustum corners world viewdir
				OUT.view_dir=FrustumCorners[(int)OUT.uv.x+2*OUT.uv.y];
				return OUT;
			}
			//物体类
			struct object
			{
				float3 position;
				//radius if sphere, half-diameter if cube
				float dimension;
				float3 color;
				float3 emission;
				int material;
				//sphere or cube
				int type;
			};
			
			#include"CustomCornellBox.cginc"//scene setup from include file
			//相交判定
			float intersectSphere(object iSphere,float3 rayDir,float3 rayOrigin)
			{
				//The line passes through p1 and p2
				//p3 is the sphere center
				float a=dot(rayDir,rayDir);
				float b=2.0*dot(rayDir,rayOrigin-iSphere.position);
				float c=dot(iSphere.position,iSphere.position)+dot(rayOrigin,rayOrigin)-2.0*dot(iSphere.position,rayOrigin)-iSphere.dimension*iSphere.dimension;
				float test=b*b-4.0*a*c;

				//取较小根
				float u=(test<0)?-1.0:(-b-sqrt(test))/(2.0*a);
				//if inside glass ball, epsilon test and take other value
				{
					u = (u <0.01 && iSphere.material == GLASS) ? (-b + sqrt(test)) / (2.0 * a) : u;
    				u = (u <0.01 && iSphere.material == GLASS) ? -1.0 : u;
				}
				return u;
			}
			float interesectBox(object iBox,float3 rayDir,float3 rayOrigin)
			{
				float t=100000;

				rayOrigin=rayOrigin-iBox.position;
				float3 n_inv=float3(1.0/rayDir.x,1.0/rayDir.y,1.0/rayDir.z);

				//AABB包围盒的最小点与最大点
				float3 bmin=float3(-1.0*iBox.dimension,-1.0*iBox.dimension,-1.0*iBox.dimension);
				float3 bmax=float3(1.0*iBox.dimension,1.0*iBox.dimension,1.0*iBox.dimension);
				//光线与垂直于X轴的两个面相交时,t=(d-O.x)/Dir.x
				//相当于计算步长
				float tx1=(bmin.x-rayOrigin.x)*n_inv.x;
				float tx2=(bmax.x-rayOrigin.x)*n_inv.x;

				float tmin=min(tx1,tx2);
				float tmax=max(tx1,tx2);

				float ty1=(bmin.y-rayOrigin.y)*n_inv.y;
				float ty2=(bmax.y-rayOrigin.y)*n_inv.y;
				tmin = max(tmin, min(ty1, ty2));
  				tmax = min(tmax, max(ty1, ty2));

				float tz1 = (bmin.z - rayOrigin.z)*n_inv.z;
  				float tz2 = (bmax.z - rayOrigin.z)*n_inv.z;

  				tmin = max(tmin, min(tz1, tz2));
  				tmax = min(tmax, max(tz1, tz2));

				if(tmin>0.01&&tmin<t&&tmax>=tmin)
				{
					return tmin;
				}
				else
				{
					return -1.0;
				}

			}
			int intersect(float3 rayDir,float3 cameraPosition,int lastHit,out float3 norm,out float minHitDist)
			{
				norm=0.0;
				minHitDist=1e9;//initialized to infinity

				float hitDist=-1.0;
				int objectHitIndex=-1;

				for(int i=0;i<NUMBER_OF_OBJECTS;i++)
				{
					if(objects[i].type==SPHERE)
					{
						float hitDist=intersectSphere(objects[i],rayDir,cameraPosition);
						//if hit and closer than the previous hits
						//in the case of glass allow self intersection check on next iteration (path inside glass object)
						if((hitDist>-1.0)&&(hitDist<=minHitDist)&&(i!=lastHit||objects[i].material==GLASS))
						{
							norm=(hitDist*rayDir+cameraPosition)-objects[i].position;
							norm=normalize(norm);
							minHitDist=hitDist;
							objectHitIndex=i;
						}
					}
					/*
					else if(objects[i].type==BOX)
					{
						float hitDist=intersectBox(objects[i],rayDir,cameraPosition);
						if ((hitDist > -1.0) && (hitDist <= minHitDist) && (i != lastHit  ||  objects[i].material == GLASS))
						{
							norm=(hitDist*rayDir+cameraPosition)-objects[i].position;
							//quick norm
							//TODO:optimize/improve
							if ( (abs(norm.x) > abs(norm.y)) && (abs(norm.x) > abs(norm.z)) )
								norm = float3(sign(norm.x) * 1.0 ,0.0,0.0);

							else if ( (abs(norm.y) > abs(norm.x)) && (abs(norm.y) > abs(norm.z)) )
								norm = float3(0.0, sign(norm.y) * 1.0 ,0.0);

							else if ( (abs(norm.z) > abs(norm.y)) && (abs(norm.z) > abs(norm.x)) )
								norm = float3(0.0,0.0,sign(norm.z) * 1.0 );

							minHitDist=hitDist;
							objectHitIndex=i;
						}
					}
					*/

				}

				return objectHitIndex;

			}
			float3 diffuseDirectionFromNormalAndAngles(float3 n,float phiAngle,float sinAngle,float cosAngle)
			{
				float3 w=normalize(n);
				float3 u=normalize(cross(w.yzx,w));
				float3 v=cross(w,u);
				return (u*cos(phiAngle)+v*sin(phiAngle))*sinAngle+w*cosAngle; 
			}
			float3 getColor(float3 rayDir,float3 cameraPosition)
			{
				float3 finalColor=float3(0.0,0.0,0.0);
				float3 aggregateColor=float3(1.0,1.0,1.0);
				int lastHit=-1;

				for(int depth=0;depth<MAX_DEPTH;depth++)
				{
					//重新发射光线位置
					float3 norm=0.0;
					float minHitDist=1e9;
					int oldHit=lastHit;

					//光线与场景的碰撞点,返回碰撞到的物体index
					lastHit=intersect(rayDir,cameraPosition,lastHit,norm,minHitDist);
					//如果没有碰撞
					if(lastHit==-1.0)
						return float3(0.0,0.0,0.0);
					//碰撞点
					float3 hitPoint=(minHitDist*rayDir)+cameraPosition;
					cameraPosition=hitPoint;
					if(objects[lastHit].material==DIFFUSE)
					{
#if defined (EXPLICIT_LIGHT_SAMPLING)
						//计算机立体角
						float3 vectorTolightSource=objects[LIGHTSOURCE_INDEX].position-hitPoint;
						float cos_a_max=sqrt(1.0-(objects[LIGHTSOURCE_INDEX].dimension*objects[LIGHTSOURCE_INDEX].dimension)/dot(vectorTolightSource,vectorTolightSource));
						float cosa=lerp(cos_a_max,1.0,rand());
						float3 randomLightDir=diffuseDirectionFromNormalAndAngles(vectorTolightSource,2.0*PI*rand(),sqrt(1.0-cosa*cosa),cosa);

						float3 lightNorm=0.0;
						float lightHitDist=1e9;

						if (intersect(randomLightDir, hitPoint, lastHit, lightNorm, lightHitDist) == LIGHTSOURCE_INDEX )
						{
							float omega = 2.0 * PI * (1.0 - cos_a_max);
							finalColor += (objects[LIGHTSOURCE_INDEX].emission * clamp(dot(randomLightDir, norm),0.0,1.0) * omega) / PI * aggregateColor * objects[lastHit].color ;
						}


						finalColor+= (objects[lastHit].emission) * aggregateColor * (float3(1.4,1.4,1.4) / objects[LIGHTSOURCE_INDEX].emission);
						aggregateColor*=objects[lastHit].color;

#else
						//our current sphere's color
						finalColor+= (objects[lastHit].emission) * aggregateColor;
						aggregateColor*=objects[lastHit].color;
#endif

						float r2 = rand();
						float3 nl = norm * sign(-dot(norm, rayDir));

						rayDir = diffuseDirectionFromNormalAndAngles(nl, 2.0*PI*rand(), sqrt(r2), sqrt(1.0 - r2));
					}
					
				}
				return finalColor;
			}
			fixed4 frag (v2f i) : SV_Target
			{
				float3 rayDir=normalize(i.view_dir);

				//像素坐标
				//设置超分辨率

				float2 pixelCoords=(i.uv)*Resolution.yx;
				float3 col=float3(0.0,0.0,0.0);
				seed=_Time.x+Resolution.y*pixelCoords.x/Resolution.x+pixelCoords.y/Resolution.y;
				for(int j=0;j<SAMPLES;j++)
				{
					//传入方向与摄像机坐标位置
					col+=getColor(rayDir,_WorldSpaceCameraPos.xyz);
				}
				col=col/float(SAMPLES);
				float2 uv=i.uv;

				float3 prevFrame=tex2D(_MainTex,uv);
				col=(col+prevFrame*float(TotalFrames))/float(TotalFrames+1);

				return float4(col,1.0);
			}
			ENDCG
		}
	}
}
