//
//  CCShaders.metal
//  002--MetalRenderMOV
//
//  Created by CC老师 on 2019/5/7.
//  Copyright © 2019年 CC老师. All rights reserved.
//

#include <metal_stdlib>

using namespace metal;
//顶点数据结构
typedef struct
{
    //顶点坐标(x,y,z,w)
    vector_float4 position;
    //纹理坐标(s,t)
    vector_float2 textureCoordinate;
} CCVertex;

//转换矩阵
typedef struct {
    //三维矩阵
    float3x3 matrix;
    //偏移量
    vector_float3 offset;
} CCConvertMatrix;

//结构体(用于顶点函数输出/片元函数输入)
typedef struct
{
    float4 clipSpacePosition [[position]]; // position的修饰符表示这个是顶点
    
    float2 textureCoordinate; // 纹理坐标
    
} RasterizerData;

//RasterizerData 返回数据类型->片元函数
// vertex_id是顶点shader每次处理的index，用于定位当前的顶点
// buffer表明是缓存数据，0是索引
vertex RasterizerData
vertexShader(uint vertexID [[ vertex_id ]],
             constant CCVertex *vertexArray [[ buffer(0) ]])
{
    RasterizerData out;
    //顶点坐标
    out.clipSpacePosition = vertexArray[vertexID].position;
    //纹理坐标
    out.textureCoordinate = vertexArray[vertexID].textureCoordinate;
    return out;
}


//YUV->RGB 参考学习链接: https://mp.weixin.qq.com/s/KKfkS5QpwPAdYcEwFAN9VA
// stage_in表示这个数据来自光栅化。（光栅化是顶点处理之后的步骤，业务层无法修改）
// texture表明是纹理数据，CCFragmentTextureIndexTextureY是索引
// texture表明是纹理数据，CCFragmentTextureIndexTextureUV是索引
// buffer表明是缓存数据， CCFragmentInputIndexMatrix是索引
fragment float4
samplingShader(RasterizerData input [[stage_in]],
               texture2d<float> textureY [[ texture(0) ]],
               texture2d<float> textureUV [[ texture(1) ]],
               texture2d<float> textureBlend [[ texture(2) ]],
               constant CCConvertMatrix *convertMatrix [[ buffer(0) ]]
               )
{
    //1.获取纹理采样器
    constexpr sampler textureSampler (mag_filter::linear,
                                      min_filter::linear);
    /*
     2. 读取YUV 颜色值
        textureY.sample(textureSampler, input.textureCoordinate).r
        从textureY中的纹理采集器中读取,纹理坐标对应上的R值.(Y)
        textureUV.sample(textureSampler, input.textureCoordinate).rg
        从textureUV中的纹理采集器中读取,纹理坐标对应上的RG值.(UV)
     */
    
    
    float3 yuv = float3(textureY.sample(textureSampler, input.textureCoordinate).r,
                        textureUV.sample(textureSampler, input.textureCoordinate).rg);
    
    float Y = textureY.sample(textureSampler, input.textureCoordinate).r;
    
    float3 rgb1 = float3(Y,Y,Y);//黑白的

    //3.将YUV 转化为 RGB值.convertMatrix->matrix * (YUV + convertMatrix->offset)
    float3 rgb = convertMatrix->matrix * (yuv + convertMatrix->offset);
    
    //混合滤镜颜色
    float4 blend = textureBlend.sample(textureSampler, input.textureCoordinate);
    return float4(rgb,1.0) * 0.4 + blend * 0.6;
    
    //4.返回颜色值(RGBA)
//    return float4(rgb, 1.0);
}

