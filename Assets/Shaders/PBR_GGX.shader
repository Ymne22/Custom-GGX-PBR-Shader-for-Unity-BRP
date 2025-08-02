Shader "YmneShader/PBR_CustomGGX_Opaque"
{
    Properties
    {
        // Other Features
        [Header(Other Features)]
        [Toggle(_TOKSVIG_SPECULAR_AA_ON)] _UseSpecularAA ("Enable Toksvig Specular AA", Float) = 0.0
        [Enum(Off, 0, Front, 1, Back, 2)] _Culling ("Culling", Float) = 2.0

        // Basic Surface Properties
        [Space(10)] [Header(Main Maps)]
        _Color ("Color", Color) = (1, 1, 1, 1)
        _MainTex ("Albedo (RGB) & Alpha (A)", 2D) = "white" {}

        // Opacity Properties
        [Space(10)] [Header(Opacity)]
        [Toggle(_CUTOUT_ON)] _UseCutout ("Enable Cutout", Float) = 0.0
        [NoScaleOffset] _OpacityMap ("Opacity Map (R)", 2D) = "white" {}
        _Cutoff ("Alpha Cutoff", Range(0.0, 1.0)) = 0.5

        // PBR Properties
        [Space(10)] [Header(PBR Maps)]
        _DielectricF0 ("Dielectric Reflectance", Color) = (0.04, 0.04, 0.04, 1)
        _SpecularIntensity ("Specular Intensity", Range(0, 1)) = 1.0
        [NoScaleOffset] _MetallicMap ("Metallic Map (R)", 2D) = "white" {}
        _Metallic ("Metallic Intensity", Range(0, 1)) = 0.0

        [Space(5)]
        [NoScaleOffset] _RoughnessMap ("Roughness Map (R)", 2D) = "white" {}
        _Roughness ("Roughness Intensity", Range(0, 1)) = 0.5

        [Space(5)]
        [NoScaleOffset] _NormalMap ("Normal Map", 2D) = "bump" {}
        _BumpScale ("Normal Intensity", Float) = 1.0

        [Space(5)]
        [NoScaleOffset] _OcclusionMap ("Occlusion Map (G)", 2D) = "white" {}
        _OcclusionStrength ("Occlusion Strength", Float) = 1.0

        // Emission Properties
        [Space(10)] [Header(Emission)]
        [ToggleUI]
        _EMISSION ("Enable Emission", Float) = 0.0
        [NoScaleOffset] _EmissionMap ("Emission Map (RGB)", 2D) = "white" {}
        [HDR] _EmissionColor ("Emission Color", Color) = (0, 0, 0, 1)
        _EmissionIntensity ("Emission Intensity", Float) = 1.0

        // Subsurface Scattering Properties
        [Space(10)] [Header(Subsurface Scattering)]
        [Toggle(_USESS_ON)] _UseSSS ("Enable Subsurface Scattering", Float) = 0.0
        [NoScaleOffset] _SubsurfaceMap ("Subsurface Map (R)", 2D) = "white" {}
        _SubsurfaceColor ("Subsurface Color", Color) = (1, 0.7725, 0.2705, 1)
        _SubsurfaceRadius ("Scatter Radius", Range(0, 5)) = 1.0
        [NoScaleOffset] _SubsurfaceThickness ("Thickness Map (R)", 2D) = "white" {}
        _ThicknessScale ("Thickness Scale", Range(0, 10)) = 1.0

        // Parallax Occlusion Mapping Properties
        [Space(10)] [Header(Parallax Occlusion Mapping)]
        [Toggle(_USEPOM_ON)] _UsePOM ("Enable Parallax Occlusion Mapping", Float) = 0.0
        [NoScaleOffset] _ParallaxMap ("Height Map (R)", 2D) = "gray" {}
        _Parallax ("Height Scale", Float) = 0.02
        _POMSamples ("POM Samples", Float) = 16.0
        _POMRefinementSteps ("POM Refinement Steps", Float) = 4.0
        [Toggle(_USEPOMSHADOWS_ON)] _UsePOMShadows ("Enable POM Self-Shadowing", Float) = 0.0
        [Toggle(_INVERTPOMSHADOWS_ON)] _InvertPOMShadows ("Invert POM Self-Shadowing", Float) = 0.0
        _POMShadowIntensity ("Shadow Intensity", Range(0, 1)) = 1.0
        _POMShadowSamples ("Shadow Samples", Float) = 16.0
        _POMShadowThreshold ("Shadow Threshold", Range(0, 0.1)) = 0.01
    }
    SubShader
    {
        Tags { "RenderType" = "TransparentCutout" "Queue" = "AlphaTest" "PerformanceChecks" = "True" }
        LOD 200

        Cull [_Culling]

        CGPROGRAM
        #pragma surface surf CustomPBR fullforwardshadows addshadow vertex:vert
        #pragma target 3.5

        #pragma shader_feature _CUTOUT_ON
        #pragma shader_feature _EMISSION
        #pragma shader_feature _USESS_ON
        #pragma shader_feature _USEPOM_ON
        #pragma shader_feature _USEPOMSHADOWS_ON
        #pragma shader_feature _INVERTPOMSHADOWS_ON
        #pragma shader_feature _TOKSVIG_SPECULAR_AA_ON

        #include "UnityPBSLighting.cginc"

        // Variable Declarations
        sampler2D _MainTex, _NormalMap, _MetallicMap, _RoughnessMap, _OcclusionMap,
        _ParallaxMap, _OpacityMap, _SubsurfaceMap, _SubsurfaceThickness, _EmissionMap;
        float4 _MainTex_ST;
        float4 _NormalMap_TexelSize;

        float _Culling;
        half _Roughness, _Metallic, _BumpScale, _OcclusionStrength,
        _Parallax, _POMSamples, _POMRefinementSteps, _POMShadowIntensity, _Cutoff, _SpecularIntensity;
        half _POMShadowSamples, _POMShadowThreshold;
        half _SubsurfaceRadius, _ThicknessScale;
        half _EmissionIntensity;
        fixed4 _Color, _SubsurfaceColor, _EmissionColor, _DielectricF0;

        struct SurfaceOutputCustom
        {
            fixed3 Albedo;
            fixed3 Normal;
            fixed3 Emission;
            half Metallic;
            half Smoothness;
            half Occlusion;
            fixed Alpha;
            float3 WorldPos;
        };

        // Custom PBR Lighting Implementation

        inline half D_GGX(half NdotH, half roughness)
        {
            half a = roughness * roughness;
            half a2 = a * a;
            half NdotH2 = NdotH * NdotH;
            half d = (NdotH2 * (a2 - 1.0) + 1.0);
            return a2 / (UNITY_PI * d * d);
        }

        inline half G_SchlickGGX(half NdotV, half roughness)
        {
            half r = roughness + 1.0;
            half k = (r * r) / 8.0;
            return NdotV / (NdotV * (1.0 - k) + k);
        }

        inline half G_Smith(half NdotV, half NdotL, half roughness)
        {
            half ggx1 = G_SchlickGGX(NdotL, roughness);
            half ggx2 = G_SchlickGGX(NdotV, roughness);
            return ggx1 * ggx2;
        }

        inline half3 F_Schlick(half cosTheta, half3 F0)
        {
            return F0 + (1.0 - F0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
        }

        half F_Fresnel_Exact(half cosTheta, half n1, half n2) {
            half cosTheta_sq = cosTheta * cosTheta;
            half sinTheta_sq = 1.0 - cosTheta_sq;
            half n_ratio = n1 / n2;
            half n_ratio_sq = n_ratio * n_ratio;
            half sinThetaT_sq = n_ratio_sq * sinTheta_sq;

            if (sinThetaT_sq > 1.0) return 1.0;

            half cosThetaT = sqrt(1.0 - sinThetaT_sq);
            half r_parallel_num = n2 * cosTheta - n1 * cosThetaT;
            half r_parallel_den = n2 * cosTheta + n1 * cosThetaT;
            half r_parallel = r_parallel_num / r_parallel_den;

            half r_perp_num = n1 * cosTheta - n2 * cosThetaT;
            half r_perp_den = n1 * cosTheta + n2 * cosThetaT;
            half r_perp = r_perp_num / r_perp_den;
            return 0.5 * (r_parallel * r_parallel + r_perp * r_perp);
        }


        inline half Fd_Disney(half NdotV, half NdotL, half LdotH, half roughness)
        {
            half Fd90 = 0.5 + 2.0 * LdotH * LdotH * (roughness * roughness);
            half lightScatter = (1.0 + (Fd90 - 1.0) * pow(1.0 - NdotL, 1.0));
            half viewScatter = (1.0 + (Fd90 - 1.0) * pow(1.0 - NdotV, 1.0));
            return lightScatter * viewScatter;
        }

        half4 LightingCustomPBR(SurfaceOutputCustom s, half3 viewDir, UnityGI gi)
        {
            half3 N = s.Normal;
            half3 V = viewDir;
            half roughness = 1.0 - s.Smoothness;
            roughness = max(roughness, 0.001h);

            half3 albedo = s.Albedo;
            half metallic = s.Metallic;

            // Direct Lighting
            half3 L = gi.light.dir;
            half3 H = normalize(V + L);
            half NdotL = saturate(dot(N, L));
            half NdotV = abs(dot(N, V));
            half NdotH = saturate(dot(N, H));
            half LdotH = saturate(dot(L, H));
            half VdotH = saturate(dot(V, H));

            half D = D_GGX(NdotH, roughness);
            half G = G_Smith(NdotV, NdotL, roughness);

            half3 F0_dielectric_val = _DielectricF0.rgb;
            half n_ior = (1.0 + sqrt(F0_dielectric_val.r)) / (1.0 - sqrt(F0_dielectric_val.r));
            half fresnel_exact_val = F_Fresnel_Exact(VdotH, 1.0, n_ior);
            half3 F_dielectric = half3(fresnel_exact_val, fresnel_exact_val, fresnel_exact_val);

            half3 F_conductor = F_Schlick(VdotH, albedo);
            half3 F = lerp(F_dielectric, F_conductor, metallic);

            half3 numerator = D * G * F;
            half denominator = 4.0 * NdotV * NdotL + 0.001;
            half3 specular = (numerator / denominator);

            half3 kS = F;
            half3 kD = (half3(1.0, 1.0, 1.0) - kS) * (1.0 - metallic);

            // This causes the specular highlight to be darker than the diffuse highlight, but i prefer to use this...
            half disneyDiffuse = Fd_Disney(NdotV, NdotL, LdotH, roughness);
            half3 diffuse = disneyDiffuse * kD * albedo / UNITY_PI;

            half3 directColor = (diffuse + specular) * gi.light.color * NdotL;

            // Indirect Lighting
            half NdotV_indirect = saturate(dot(N, V));
            half fresnel_exact_indirect = F_Fresnel_Exact(NdotV_indirect, 1.0, n_ior);
            half3 F_dielectric_indirect = half3(fresnel_exact_indirect, fresnel_exact_indirect, fresnel_exact_indirect);
            half3 F_conductor_indirect = F_Schlick(NdotV_indirect, albedo);
            half3 F_indirect = lerp(F_dielectric_indirect, F_conductor_indirect, metallic);

            half3 kS_indirect = F_indirect;
            half3 kD_indirect = (1.0 - kS_indirect) * (1.0 - metallic);
            
            // Simplified diffuse factor

            half3 indirectDiffuse = gi.indirect.diffuse * albedo * kD_indirect;
            half3 reflection = gi.indirect.specular;
            half3 indirectSpecular = reflection * kS_indirect;

            // Final Color
            half3 finalColor = directColor + (indirectDiffuse + indirectSpecular) * s.Occlusion;
            finalColor += s.Emission; // Add emission here

            return half4(finalColor, s.Alpha);
        }

        // GI function now uses SurfaceOutputCustom
        void LightingCustomPBR_GI(SurfaceOutputCustom s, UnityGIInput data, inout UnityGI gi)
        {
            half3 F0 = lerp(_DielectricF0.rgb, s.Albedo, s.Metallic);
            Unity_GlossyEnvironmentData g = UnityGlossyEnvironmentSetup(s.Smoothness, data.worldViewDir, s.Normal, F0);
            gi = UnityGlobalIllumination(data, s.Occlusion, s.Normal, g);
        }

        struct Input
        {
            float2 customTiledUV;
            float3 viewDir;
            float3 lightDir;
            float vface : VFACE;
            float3 worldPos;
        };
        void vert (inout appdata_full v, out Input o)
        {
            UNITY_INITIALIZE_OUTPUT(Input, o);
            o.customTiledUV = v.texcoord.xy * _MainTex_ST.xy + _MainTex_ST.zw;

            TANGENT_SPACE_ROTATION;
            o.viewDir = mul(rotation, ObjSpaceViewDir(v.vertex));
            o.lightDir = mul(rotation, ObjSpaceLightDir(v.vertex));
            o.worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;
        }

        half3 CalculateSubsurfaceScattering(Input IN, half3 normal, half3 albedo, half roughness, half thickness)
        {
            #if !defined(_USESS_ON)
            return half3(0, 0, 0);
            #endif
            half3 sss = 0;
            half3 viewDir = normalize(IN.viewDir);
            const half3 diffusionKernel[3] = {
                half3(0.233, 0.455, 0.649),
                half3(0.100, 0.336, 0.344),
                half3(0.118, 0.198, 0.000)
            };
            half3 H = normalize(IN.lightDir + normal * _SubsurfaceRadius);
            half dotNL = saturate(dot(normal, IN.lightDir));
            half dotLH = saturate(dot(IN.lightDir, H));
            half dotNH = saturate(dot(normal, H));
            half scatter = 1.0 / (1.0 + (dotLH * dotLH) * (roughness * roughness - 1.0));
            half transmission = pow(saturate(1.0 - dotNL), _SubsurfaceRadius) * thickness;

            [unroll(3)]
            for (int i = 0; i < 3; i ++)
            {
                half3 scatterDir = normalize(normal + (diffusionKernel[i] - 0.5) * 2.0);
                sss += diffusionKernel[i].z * albedo * transmission * scatter;
            }
            return sss * _SubsurfaceColor.rgb;
        }

        void surf (Input IN, inout SurfaceOutputCustom o)
        {
            float2 uv = IN.customTiledUV;
            half shadow = 1.0;

            #if defined(_USEPOM_ON)
            float3 viewDir = normalize(IN.viewDir);
            float stepSize = 1.0 / _POMSamples;
            float2 uvStep = - ((viewDir.xy * _Parallax) * stepSize);

            float2 currentUV = IN.customTiledUV;
            float currentHeight = 1.0;

            float2 ddx_uv = ddx(IN.customTiledUV);
            float2 ddy_uv = ddy(IN.customTiledUV);
            [loop]
            for (int i = 0; i < _POMSamples; i ++)
            {
                currentHeight -= stepSize;
                currentUV += uvStep;
                float sampledHeight = tex2Dgrad(_ParallaxMap, currentUV, ddx_uv, ddy_uv).r;
                if (sampledHeight > currentHeight)
                {
                    float2 frontUV = currentUV - uvStep;
                    float2 backUV = currentUV;
                    float frontRayHeight = currentHeight + stepSize;
                    float backRayHeight = currentHeight;

                    int numRefinementSteps = (int)_POMRefinementSteps;
                    [loop]
                    for (int k = 0; k < numRefinementSteps; k ++)
                    {
                        float2 midUV = (frontUV + backUV) * 0.5;
                        float midRayHeight = (frontRayHeight + backRayHeight) * 0.5;
                        float midSampledHeight = tex2Dgrad(_ParallaxMap, midUV, ddx_uv, ddy_uv).r;
                        if (midSampledHeight > midRayHeight) {
                            backUV = midUV;
                            backRayHeight = midRayHeight;
                        } else {
                            frontUV = midUV;
                            frontRayHeight = midRayHeight;
                        }
                    }
                    currentUV = (frontUV + backUV) * 0.5;
                    currentHeight = (frontRayHeight + backRayHeight) * 0.5;
                    break;
                }
            }
            uv = currentUV;
            #if defined(_USEPOMSHADOWS_ON)
            float3 lightDir = normalize(IN.lightDir);
            float shadowStep = 1.0 / _POMShadowSamples;
            float2 shadowUVStep = ((lightDir.xy * _Parallax) * shadowStep);
            #if defined(_INVERTPOMSHADOWS_ON)
            shadowUVStep *= - 1;
            #endif

            float2 shadowUV = uv;
            float shadowHeight = currentHeight;

            [loop]
            for (int j = 1; j < (int)_POMShadowSamples; j ++)
            {
                shadowHeight += shadowStep;
                shadowUV += shadowUVStep;
                float sampledHeight = tex2Dgrad(_ParallaxMap, shadowUV, ddx_uv, ddy_uv).r;
                if (sampledHeight > shadowHeight + _POMShadowThreshold)
                {
                    shadow = 1.0 - _POMShadowIntensity;
                    break;
                }
            }
            #endif
            #endif

            fixed4 c = tex2D(_MainTex, uv) * _Color;
            half alpha = c.a * tex2D(_OpacityMap, uv).r;

            #if defined(_CUTOUT_ON)
            clip(alpha - _Cutoff);
            #endif

            o.Albedo = c.rgb * shadow;
            float4 packedNormal;
            float roughnessMapValue = tex2D(_RoughnessMap, uv).r;
            float roughnessValue = roughnessMapValue * _Roughness;
            #if defined(_TOKSVIG_SPECULAR_AA_ON)
            float2 duv_dx = ddx(IN.customTiledUV);
            float2 duv_dy = ddy(IN.customTiledUV);
            float mip = 0.5 * log2(max(dot(duv_dx, duv_dx), dot(duv_dy, duv_dy)));
            mip += roughnessValue * roughnessValue * 4.0;
            float mip_floor = floor(mip);
            float mip_ceil = ceil(mip);
            float mip_frac = frac(mip);
            float4 normal_low = tex2Dlod(_NormalMap, float4(uv, 0, mip_floor));
            float4 normal_high = tex2Dlod(_NormalMap, float4(uv, 0, mip_ceil));
            packedNormal = lerp(normal_low, normal_high, mip_frac);
            #else
            packedNormal = tex2D(_NormalMap, uv);
            #endif

            o.Normal = UnpackScaleNormal(packedNormal, _BumpScale);
            if (_Culling == 0) {
                o.Normal *= IN.vface;
            }

            o.Metallic = tex2D(_MetallicMap, uv).r * _Metallic;
            o.Smoothness = (1.0 - roughnessValue) * _SpecularIntensity;
            o.Occlusion = lerp(1, tex2D(_OcclusionMap, uv).g, _OcclusionStrength);
            o.WorldPos = IN.worldPos;

            o.Emission = 0; // Initialize Emission
            #if defined(_USESS_ON)
            half thickness = tex2D(_SubsurfaceThickness, uv).r * _ThicknessScale;
            half sssMask = tex2D(_SubsurfaceMap, uv).r;
            half3 subsurface = CalculateSubsurfaceScattering(IN, o.Normal, o.Albedo, 1 - o.Smoothness, thickness);
            o.Albedo *= (1.0 - sssMask * 0.5);
            o.Emission = subsurface * sssMask;
            #elif defined(_EMISSION)
            fixed3 emission = tex2D(_EmissionMap, uv).rgb * _EmissionColor.rgb * _EmissionIntensity;
            o.Emission = emission;
            #endif

            o.Alpha = 1.0;
        }
        ENDCG

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }

            ZWrite On
            ZTest LEqual
            Cull [_Culling]

            CGPROGRAM
            #pragma vertex vert_shadow
            #pragma fragment frag_shadow
            #pragma multi_compile_shadowcaster
            #pragma shader_feature _CUTOUT_ON
            #pragma shader_feature _USEPOM_ON

            #include "UnityCG.cginc"

            struct v2f_shadow
            {
                V2F_SHADOW_CASTER;
                float2 uv : TEXCOORD1;
                float3 viewDir : TEXCOORD2;
            };

            sampler2D _MainTex, _OpacityMap, _ParallaxMap;
            float4 _MainTex_ST;
            fixed4 _Color;
            half _Cutoff, _Parallax, _POMSamples, _POMRefinementSteps;

            v2f_shadow vert_shadow(appdata_full v)
            {
                v2f_shadow o;
                UNITY_INITIALIZE_OUTPUT(v2f_shadow, o);
                TRANSFER_SHADOW_CASTER_NORMALOFFSET(o)
                o.uv = v.texcoord.xy * _MainTex_ST.xy + _MainTex_ST.zw;
                TANGENT_SPACE_ROTATION;
                o.viewDir = mul(rotation, ObjSpaceViewDir(v.vertex));
                return o;
            }

            fixed4 frag_shadow(v2f_shadow i) : SV_Target
            {
                float2 uv = i.uv;
                #if defined(_USEPOM_ON)
                float3 viewDir = normalize(i.viewDir);
                float stepSize = 1.0 / _POMSamples;
                float2 uvStep = - ((viewDir.xy * _Parallax) * stepSize);

                float2 currentUV = i.uv;
                float currentHeight = 1.0;

                float2 ddx_uv = ddx(i.uv);
                float2 ddy_uv = ddy(i.uv);
                [loop]
                for (int pom_i = 0; pom_i < _POMSamples; pom_i ++)
                {
                    currentHeight -= stepSize;
                    currentUV += uvStep;
                    float sampledHeight = tex2Dgrad(_ParallaxMap, currentUV, ddx_uv, ddy_uv).r;
                    if (sampledHeight > currentHeight)
                    {
                        float2 frontUV = currentUV - uvStep;
                        float2 backUV = currentUV;
                        float frontRayHeight = currentHeight + stepSize;
                        float backRayHeight = currentHeight;

                        int numRefinementSteps = (int)_POMRefinementSteps;
                        [loop]
                        for (int k = 0; k < numRefinementSteps; k ++)
                        {
                            float2 midUV = (frontUV
                            + backUV) * 0.5;
                            float midRayHeight = (frontRayHeight + backRayHeight) * 0.5;
                            float midSampledHeight = tex2Dgrad(_ParallaxMap, midUV, ddx_uv, ddy_uv).r;
                            if (midSampledHeight > midRayHeight) {
                                backUV = midUV;
                                backRayHeight = midRayHeight;
                            } else {
                                frontUV = midUV;
                                frontRayHeight = midRayHeight;
                            }
                        }
                        currentUV = (frontUV + backUV) * 0.5;
                        break;
                    }
                }
                uv = currentUV;
                #endif

                fixed4 tex = tex2D(_MainTex, uv) * _Color;
                half alpha = tex.a * tex2D(_OpacityMap, uv).r;

                #if defined(_CUTOUT_ON)
                clip(alpha - _Cutoff);
                #endif

                SHADOW_CASTER_FRAGMENT(i)
            }
            ENDCG
        }

        Pass
        {
            Name "Meta"
            Tags { "LightMode" = "Meta" }

            Cull Off

            CGPROGRAM
            #pragma vertex vert_meta
            #pragma fragment frag_meta
            #pragma shader_feature _EMISSION
            #pragma shader_feature _CUTOUT_ON

            #include "UnityCG.cginc"
            #include "UnityMetaPass.cginc"

            sampler2D _MainTex;
            sampler2D _EmissionMap;
            sampler2D _OpacityMap;
            float4 _MainTex_ST;
            fixed4 _Color;
            fixed4 _EmissionColor;
            half _EmissionIntensity;
            half _Cutoff;

            struct v2f_meta
            {
                float4 pos : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            v2f_meta vert_meta(appdata_full v)
            {
                v2f_meta o;
                o.pos = UnityMetaVertexPosition(v.vertex, v.texcoord1.xy, v.texcoord2.xy, unity_LightmapST, unity_DynamicLightmapST);
                o.uv = v.texcoord.xy * _MainTex_ST.xy + _MainTex_ST.zw;
                return o;
            }

            fixed4 frag_meta(v2f_meta i) : SV_Target
            {
                UnityMetaInput metaIN;
                UNITY_INITIALIZE_OUTPUT(UnityMetaInput, metaIN);

                fixed4 albedo = tex2D(_MainTex, i.uv) * _Color;

                #if defined(_CUTOUT_ON)
                half alpha = albedo.a * tex2D(_OpacityMap, i.uv).r;
                clip(alpha - _Cutoff);
                #endif

                metaIN.Albedo = albedo.rgb;
                #if defined(_EMISSION)
                metaIN.Emission = tex2D(_EmissionMap, i.uv).rgb * _EmissionColor.rgb * _EmissionIntensity;
                #endif

                return UnityMetaFragment(metaIN);
            }
            ENDCG
        }
    }
    FallBack "Diffuse"
    CustomEditor "ShaderForgeMaterialInspector"
}