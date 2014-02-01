//
//  SSViewController.m
//  ParticleEmitterDemoGLKit+ARC
//
//  Created by Tom Bradley on 28/01/2014.
//  Copyright (c) 2014 Tom Bradley. All rights reserved.
//

#import "SSViewController.h"
#import "ParticleEmitter.h"

@interface SSViewController () {
}

@property (strong, nonatomic) EAGLContext       *context;
@property (strong, nonatomic) GLKBaseEffect     *effect;
@property (strong, nonatomic) ParticleEmitter   *pe;
@property (strong, nonatomic) GLKBaseEffect     *particleEmitterEffect;

- (void)setupGL;
- (void)tearDownGL;

@end

@implementation SSViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];

    if (!self.context) {
        NSLog(@"Failed to create ES context");
    }
    
    GLKView *view = (GLKView *)self.view;
    view.context = self.context;
    view.drawableDepthFormat = GLKViewDrawableDepthFormat24;
    
    [self setupGL];
}

- (void)dealloc
{    
    [self tearDownGL];
    
    if ([EAGLContext currentContext] == self.context) {
        [EAGLContext setCurrentContext:nil];
    }
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];

    if ([self isViewLoaded] && ([[self view] window] == nil)) {
        self.view = nil;
        
        [self tearDownGL];
        
        if ([EAGLContext currentContext] == self.context) {
            [EAGLContext setCurrentContext:nil];
        }
        self.context = nil;
    }

    // Dispose of any resources that can be recreated.
}

- (void)setupGL
{
    [EAGLContext setCurrentContext:self.context];
    
    // get screen bounds
    CGRect bounds = [[UIScreen mainScreen] bounds];
    
    // Setup the shader to be used for rendering particles
    self.particleEmitterEffect = [[GLKBaseEffect alloc] init];
    self.particleEmitterEffect.texture2d0.envMode = GLKTextureEnvModeModulate;
    self.particleEmitterEffect.useConstantColor = GL_FALSE;
    self.particleEmitterEffect.transform.projectionMatrix = GLKMatrix4MakeOrtho(0, bounds.size.width, 0, bounds.size.height, 0, 1);
    
    //_pe = [[ParticleEmitter alloc] initParticleEmitterWithFile:@"Comet.pex" effectShader:self.particleEmitterEffect];
    _pe = [[ParticleEmitter alloc] initParticleEmitterWithFile:@"Blue Flame.pex" effectShader:self.particleEmitterEffect];
    //_pe = [[ParticleEmitter alloc] initParticleEmitterWithFile:@"Crazy Blue.pex" effectShader:self.particleEmitterEffect];

    glEnable(GL_BLEND);
}

- (void)tearDownGL
{
    [EAGLContext setCurrentContext:self.context];
    self.effect = nil;
}

#pragma mark - GLKView and GLKViewController delegate methods

- (void)update
{
    [_pe updateWithDelta:self.timeSinceLastUpdate];
}

- (void)glkView:(GLKView *)view drawInRect:(CGRect)rect
{
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    [_pe renderParticles];
}

@end
