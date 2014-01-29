//
//  Shader.fsh
//  ParticleEmitterDemoES2+ARC
//
//  Created by Tom Bradley on 28/01/2014.
//  Copyright (c) 2014 Tom Bradley. All rights reserved.
//

varying lowp vec4 colorVarying;

void main()
{
    gl_FragColor = colorVarying;
}
