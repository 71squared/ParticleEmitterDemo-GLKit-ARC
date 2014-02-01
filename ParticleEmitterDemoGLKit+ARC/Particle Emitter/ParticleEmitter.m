//
//  ParticleEmitter.m
//  ParticleEmitterDemo
//
// Copyright (c) 2010 71Squared
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//
// The design and code for the ParticleEmitter were heavely influenced by the design and code
// used in Cocos2D for their particle system.

#import "ParticleEmitter.h"
#import "TBXML.h"
#import "TBXMLParticleAdditions.h"
#import "TBXML+Compression.h"

#pragma mark -
#pragma mark Private interface

@interface ParticleEmitter (Private)

// Adds a particle from the particle pool to the emitter
- (BOOL)addParticle;

// Initialises a particle ready for use
- (void)initParticle:(Particle*)particle;

// Parses the supplied XML particle configuration file
- (void)parseParticleConfig:(TBXML*)aConfig;

// Set up the arrays that are going to store our particles
- (void)setupArrays;

@end

#pragma mark -
#pragma mark Public implementation

@implementation ParticleEmitter

@synthesize sourcePosition;
@synthesize active;
@synthesize particleCount;
@synthesize duration;

- (void)dealloc {
	
	// Release the memory we are using for our vertex and particle arrays etc
	// If vertices or particles exist then free them
	if (quads) 
		free(quads);
    
	if (particles)
		free(particles);
	
	// Release the VBOs created
	glDeleteBuffers(1, &verticesID);
}

- (id)initParticleEmitterWithFile:(NSString*)aFileName  effectShader:(GLKBaseEffect*)aShaderEffect {
		self = [super init];
		if (self != nil) {
			
            shaderEffect = aShaderEffect;
            
            NSError *error;
            
			// Create a TBXML instance that we can use to parse the config file
			TBXML *particleXML = [[TBXML alloc] initWithXMLFile:aFileName error:&error];
            
            if (!error) {
                // Parse the config file
                [self parseParticleConfig:particleXML];
                
                [self setupArrays];
            }
		}
		return self;
}

- (void)updateWithDelta:(GLfloat)aDelta {

	// If the emitter is active and the emission rate is greater than zero then emit particles
	if (active && emissionRate) {
		float rate = 1.0f/emissionRate;
		emitCounter += aDelta;
		while (particleCount < maxParticles && emitCounter > rate) {
			[self addParticle];
			emitCounter -= rate;
		}

		elapsedTime += aDelta;
		if (duration != -1 && duration < elapsedTime)
			[self stopParticleEmitter];
	}
	
	// Reset the particle index before updating the particles in this emitter
	particleIndex = 0;
    
    // Loop through all the particles updating their location and color
	while (particleIndex < particleCount) {

		// Get the particle for the current particle index
		Particle *currentParticle = &particles[particleIndex];
        
        // FIX 1
        // Reduce the life span of the particle
        currentParticle->timeToLive -= aDelta;
		
		// If the current particle is alive then update it
		if (currentParticle->timeToLive > 0) {
			
			// If maxRadius is greater than 0 then the particles are going to spin otherwise they are effected by speed and gravity
			if (emitterType == kParticleTypeRadial) {

                // FIX 2
                // Update the angle of the particle from the sourcePosition and the radius.  This is only done of the particles are rotating
				currentParticle->angle += currentParticle->degreesPerSecond * aDelta;
				currentParticle->radius -= currentParticle->radiusDelta;
                
				GLKVector2 tmp;
				tmp.x = sourcePosition.x - cosf(currentParticle->angle) * currentParticle->radius;
				tmp.y = sourcePosition.y - sinf(currentParticle->angle) * currentParticle->radius;
				currentParticle->position = tmp;

				if (currentParticle->radius < minRadius)
					currentParticle->timeToLive = 0;
                
			} else {
				GLKVector2 tmp, radial, tangential;
                
                radial = GLKVector2Zero;
                GLKVector2 diff = GLKVector2Subtract(currentParticle->startPos, GLKVector2Zero);
                
                currentParticle->position = GLKVector2Subtract(currentParticle->position, diff);
                
                if (currentParticle->position.x || currentParticle->position.y)
                    radial = GLKVector2Normalize(currentParticle->position);
                
                tangential.x = radial.x;
                tangential.y = radial.y;
                radial = GLKVector2Multiply(radial, GLKVector2Make(currentParticle->radialAcceleration, currentParticle->radialAcceleration));
                
                GLfloat newy = tangential.x;
                tangential.x = -tangential.y;
                tangential.y = newy;
                tangential = GLKVector2Multiply(tangential, GLKVector2Make(currentParticle->tangentialAcceleration, currentParticle->tangentialAcceleration));
                
				tmp = GLKVector2Add( GLKVector2Add(radial, tangential), gravity);
                tmp = GLKVector2Multiply(tmp, GLKVector2Make(aDelta, aDelta));
				currentParticle->direction = GLKVector2Add(currentParticle->direction, tmp);
				tmp = GLKVector2Multiply(currentParticle->direction, GLKVector2Make(aDelta,aDelta));
				currentParticle->position = GLKVector2Add(currentParticle->position, tmp);
                currentParticle->position = GLKVector2Add(currentParticle->position, diff);
			}
			
			// Update the particles color
			currentParticle->color.r += currentParticle->deltaColor.r;
			currentParticle->color.g += currentParticle->deltaColor.g;
			currentParticle->color.b += currentParticle->deltaColor.b;
			currentParticle->color.a += currentParticle->deltaColor.a;
			
			// Update the particle size
			currentParticle->particleSize += currentParticle->particleSizeDelta;

            // Update the rotation of the particle
            currentParticle->rotation += (currentParticle->rotationDelta * aDelta);

            // As we are rendering the particles as quads, we need to define 6 vertices for each particle
            GLfloat halfSize = currentParticle->particleSize * 0.5f;

            // If a rotation has been defined for this particle then apply the rotation to the vertices that define
            // the particle
            if (currentParticle->rotation) {
                float x1 = -halfSize;
                float y1 = -halfSize;
                float x2 = halfSize;
                float y2 = halfSize;
                float x = currentParticle->position.x;
                float y = currentParticle->position.y;
                float r = (float)DEGREES_TO_RADIANS(currentParticle->rotation);
                float cr = cosf(r);
                float sr = sinf(r);
                float ax = x1 * cr - y1 * sr + x;
                float ay = x1 * sr + y1 * cr + y;
                float bx = x2 * cr - y1 * sr + x;
                float by = x2 * sr + y1 * cr + y;
                float cx = x2 * cr - y2 * sr + x;
                float cy = x2 * sr + y2 * cr + y;
                float dx = x1 * cr - y2 * sr + x;
                float dy = x1 * sr + y2 * cr + y;
                
                quads[particleIndex].bl.vertex.x = ax;
                quads[particleIndex].bl.vertex.y = ay;
                quads[particleIndex].bl.color = currentParticle->color;
                
                quads[particleIndex].br.vertex.x = bx;
                quads[particleIndex].br.vertex.y = by;
                quads[particleIndex].br.color = currentParticle->color;
                
                quads[particleIndex].tl.vertex.x = dx;
                quads[particleIndex].tl.vertex.y = dy;
                quads[particleIndex].tl.color = currentParticle->color;
                
                quads[particleIndex].tr.vertex.x = cx;
                quads[particleIndex].tr.vertex.y = cy;
                quads[particleIndex].tr.color = currentParticle->color;
            } else {
                // Using the position of the particle, work out the four vertices for the quad that will hold the particle
                // and load those into the quads array.
                quads[particleIndex].bl.vertex.x = currentParticle->position.x - halfSize;
                quads[particleIndex].bl.vertex.y = currentParticle->position.y - halfSize;
                quads[particleIndex].bl.color = currentParticle->color;
                
                quads[particleIndex].br.vertex.x = currentParticle->position.x + halfSize;
                quads[particleIndex].br.vertex.y = currentParticle->position.y - halfSize;
                quads[particleIndex].br.color = currentParticle->color;
                
                quads[particleIndex].tl.vertex.x = currentParticle->position.x - halfSize;
                quads[particleIndex].tl.vertex.y = currentParticle->position.y + halfSize;
                quads[particleIndex].tl.color = currentParticle->color;
                
                quads[particleIndex].tr.vertex.x = currentParticle->position.x + halfSize;
                quads[particleIndex].tr.vertex.y = currentParticle->position.y + halfSize;
                quads[particleIndex].tr.color = currentParticle->color;
            }

			// Update the particle and vertex counters
			particleIndex++;
		} else {

			// As the particle is not alive anymore replace it with the last active particle 
			// in the array and reduce the count of particles by one.  This causes all active particles
			// to be packed together at the start of the array so that a particle which has run out of
			// life will only drop into this clause once
			if (particleIndex != particleCount - 1)
				particles[particleIndex] = particles[particleCount - 1];
            
			particleCount--;
		}
	}
}

- (void)stopParticleEmitter {
	active = NO;
	elapsedTime = 0;
	emitCounter = 0;
}

- (void)renderParticles {
    
    shaderEffect.texture2d0.name = texture.name;
    shaderEffect.texture2d0.enabled = YES;
    
    [shaderEffect prepareToDraw];
    
    glEnableVertexAttribArray(GLKVertexAttribPosition);
    glEnableVertexAttribArray(GLKVertexAttribTexCoord0);
    glEnableVertexAttribArray(GLKVertexAttribColor);
    
	// Bind to the verticesID VBO and popuate it with the necessary vertex, color and texture informaiton
	glBindBuffer(GL_ARRAY_BUFFER, verticesID);
    
    // Using glBufferSubData means that a copy is done from the quads array to the buffer rather than recreating the buffer which
    // would be an allocation and copy. The copy also only takes over the number of live particles. This provides a nice performance
    // boost.
    glBufferSubData(GL_ARRAY_BUFFER, 0, sizeof(ParticleQuad) * particleIndex, quads);

	// Configure the vertex pointer which will use the currently bound VBO for its data
    glVertexAttribPointer(GLKVertexAttribPosition, 2, GL_FLOAT, GL_FALSE, sizeof(TexturedColoredVertex), 0);
    glVertexAttribPointer(GLKVertexAttribColor, 4, GL_FLOAT, GL_FALSE, sizeof(TexturedColoredVertex), (GLvoid*) offsetof(TexturedColoredVertex, color));
    glVertexAttribPointer(GLKVertexAttribTexCoord0, 2, GL_FLOAT, GL_FALSE, sizeof(TexturedColoredVertex), (GLvoid*) offsetof(TexturedColoredVertex, texture));
	   
    // Set the blend function based on the configuration
    glBlendFunc(blendFuncSource, blendFuncDestination);
    //NSLog(@"%i %i", blendFuncSource, blendFuncDestination);
    
    //glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
	
	// Now that all of the VBOs have been used to configure the vertices, pointer size and color
	// use glDrawArrays to draw the points
    glDrawElements(GL_TRIANGLES, particleIndex * 6, GL_UNSIGNED_SHORT, indices);

	// Unbind the current VBO
	glBindBuffer(GL_ARRAY_BUFFER, 0);
    
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);	
}

@end

#pragma mark -
#pragma mark Private implementation

@implementation ParticleEmitter (Private)

- (BOOL)addParticle {
	
	// If we have already reached the maximum number of particles then do nothing
	if (particleCount == maxParticles)
		return NO;
	
	// Take the next particle out of the particle pool we have created and initialize it
	Particle *particle = &particles[particleCount];
	[self initParticle:particle];
	
	// Increment the particle count
	particleCount++;
	
	// Return YES to show that a particle has been created
	return YES;
}


- (void)initParticle:(Particle*)particle {
	
	// Init the position of the particle.  This is based on the source position of the particle emitter
	// plus a configured variance.  The RANDOM_MINUS_1_TO_1 macro allows the number to be both positive
	// and negative
	particle->position.x = sourcePosition.x + sourcePositionVariance.x * RANDOM_MINUS_1_TO_1();
	particle->position.y = sourcePosition.y + sourcePositionVariance.y * RANDOM_MINUS_1_TO_1();
    particle->startPos.x = sourcePosition.x;
    particle->startPos.y = sourcePosition.y;
	
	// Init the direction of the particle.  The newAngle is calculated using the angle passed in and the
	// angle variance.
	float newAngle = (GLfloat)DEGREES_TO_RADIANS(angle + angleVariance * RANDOM_MINUS_1_TO_1());
	
	// Create a new GLKVector2 using the newAngle
	GLKVector2 vector = GLKVector2Make(cosf(newAngle), sinf(newAngle));
	
	// Calculate the vectorSpeed using the speed and speedVariance which has been passed in
	float vectorSpeed = speed + speedVariance * RANDOM_MINUS_1_TO_1();
	
	// The particles direction vector is calculated by taking the vector calculated above and
	// multiplying that by the speed
	particle->direction = GLKVector2Multiply(vector, GLKVector2Make(vectorSpeed, vectorSpeed));
	
	// Set the default diameter of the particle from the source position
	particle->radius = maxRadius + maxRadiusVariance * RANDOM_MINUS_1_TO_1();
	particle->radiusDelta = (maxRadius / particleLifespan) * (1.0 / MAXIMUM_UPDATE_RATE);
	particle->angle = DEGREES_TO_RADIANS(angle + angleVariance * RANDOM_MINUS_1_TO_1());
	particle->degreesPerSecond = DEGREES_TO_RADIANS(rotatePerSecond + rotatePerSecondVariance * RANDOM_MINUS_1_TO_1());
    
    particle->radialAcceleration = radialAcceleration;
    particle->tangentialAcceleration = tangentialAcceleration;
	
	// Calculate the particles life span using the life span and variance passed in
	particle->timeToLive = MAX(0, particleLifespan + particleLifespanVariance * RANDOM_MINUS_1_TO_1());
	
	// Calculate the particle size using the start and finish particle sizes
	GLfloat particleStartSize = startParticleSize + startParticleSizeVariance * RANDOM_MINUS_1_TO_1();
	GLfloat particleFinishSize = finishParticleSize + finishParticleSizeVariance * RANDOM_MINUS_1_TO_1();
	particle->particleSizeDelta = ((particleFinishSize - particleStartSize) / particle->timeToLive) * (1.0 / MAXIMUM_UPDATE_RATE);
	particle->particleSize = MAX(0, particleStartSize);
	
	// Calculate the color the particle should have when it starts its life.  All the elements
	// of the start color passed in along with the variance are used to calculate the star color
	GLKVector4 start = {0, 0, 0, 0};
	start.r = startColor.r + startColorVariance.r * RANDOM_MINUS_1_TO_1();
	start.g = startColor.g + startColorVariance.g * RANDOM_MINUS_1_TO_1();
	start.b = startColor.b + startColorVariance.b * RANDOM_MINUS_1_TO_1();
	start.a = startColor.a + startColorVariance.a * RANDOM_MINUS_1_TO_1();
	
	// Calculate the color the particle should be when its life is over.  This is done the same
	// way as the start color above
	GLKVector4 end = {0, 0, 0, 0};
	end.r = finishColor.r + finishColorVariance.r * RANDOM_MINUS_1_TO_1();
	end.g = finishColor.g + finishColorVariance.g * RANDOM_MINUS_1_TO_1();
	end.b = finishColor.b + finishColorVariance.b * RANDOM_MINUS_1_TO_1();
	end.a = finishColor.a + finishColorVariance.a * RANDOM_MINUS_1_TO_1();
	
	// Calculate the delta which is to be applied to the particles color during each cycle of its
	// life.  The delta calculation uses the life span of the particle to make sure that the 
	// particles color will transition from the start to end color during its life time.  As the game
	// loop is using a fixed delta value we can calculate the delta color once saving cycles in the 
	// update method
	particle->color = start;
	particle->deltaColor.r = ((end.r - start.r) / particle->timeToLive) * (1.0 / MAXIMUM_UPDATE_RATE);
	particle->deltaColor.g = ((end.g - start.g) / particle->timeToLive)  * (1.0 / MAXIMUM_UPDATE_RATE);
	particle->deltaColor.b = ((end.b - start.b) / particle->timeToLive)  * (1.0 / MAXIMUM_UPDATE_RATE);
	particle->deltaColor.a = ((end.a - start.a) / particle->timeToLive)  * (1.0 / MAXIMUM_UPDATE_RATE);
    
    // Calculate the rotation
    GLfloat startA = rotationStart + rotationStartVariance * RANDOM_MINUS_1_TO_1();
    GLfloat endA = rotationEnd + rotationEndVariance * RANDOM_MINUS_1_TO_1();
    particle->rotation = startA;
    particle->rotationDelta = (endA - startA) / particle->timeToLive;

}

- (void)parseParticleConfig:(TBXML*)aConfig {

	TBXMLElement *rootXMLElement = aConfig.rootXMLElement;
	
	// Make sure we have a root element or we cant process this file
    NSAssert(rootXMLElement, @"ERROR - ParticleEmitter: Could not find root element in particle config file.");
	
	// First thing to grab is the texture that is to be used for the point sprite
	TBXMLElement *element = [TBXML childElementNamed:@"texture" parentElement:rootXMLElement];
	if (element) {
		NSString *fileName = [TBXML valueOfAttributeNamed:@"name" forElement:element];
        NSString *fileData = [TBXML valueOfAttributeNamed:@"data" forElement:element];
        
        // Set up options for GLKTextureLoader
        NSDictionary * options = [NSDictionary dictionaryWithObjectsAndKeys:
                                  [NSNumber numberWithBool:YES],
                                  GLKTextureLoaderOriginBottomLeft,
                                  [NSNumber numberWithBool:YES],
                                  GLKTextureLoaderApplyPremultiplication,
                                  nil];
        
        NSError *error;
        
        if (fileName && !fileData) {
            // Get path to resource
            NSString *path = [[NSBundle mainBundle] pathForResource:fileName ofType:nil];
            
            // If no path is passed back then something is wrong
            NSAssert1(path, @"Unable to find texture file: %@", path);
            
			// Create a new texture which is going to be used as the texture for the point sprites. As there is
            // no texture data in the file, this is done using an external image file
			texture = [GLKTextureLoader textureWithContentsOfFile:path options:options error:&error];
            
            // Throw assersion error if loading texture failed
            NSAssert(!error, @"Unable to load texture");
		}
        
        // If texture data is present in the file then create the texture image from that data rather than an external file
        else if (fileData) {
            // Decode compressed data from pex
            NSData *tiffData = [[[NSData alloc] initWithBase64EncodedString:fileData] gzipInflate];
            
            // Use GLKTextureLoader to load the tiff data into a texture
            texture = [GLKTextureLoader textureWithContentsOfData:tiffData options:options error:&error];

            // Throw assersion error if loading texture failed
            NSAssert(!error, @"Unable to load texture");
        }
	}
	
	// Load all of the values from the XML file into the particle emitter.  The functions below are using the
	// TBXMLAdditions category.  This adds convenience methods to TBXML to help cut down on the code in this method.
    emitterType                 = [aConfig intValueFromChildElementNamed:@"emitterType" parentElement:rootXMLElement];
	sourcePosition              = [aConfig glkVector2FromChildElementNamed:@"sourcePosition" parentElement:rootXMLElement];
	sourcePositionVariance      = [aConfig glkVector2FromChildElementNamed:@"sourcePositionVariance" parentElement:rootXMLElement];
	speed                       = [aConfig floatValueFromChildElementNamed:@"speed" parentElement:rootXMLElement];
	speedVariance               = [aConfig floatValueFromChildElementNamed:@"speedVariance" parentElement:rootXMLElement];
	particleLifespan            = [aConfig floatValueFromChildElementNamed:@"particleLifeSpan" parentElement:rootXMLElement];
	particleLifespanVariance    = [aConfig floatValueFromChildElementNamed:@"particleLifespanVariance" parentElement:rootXMLElement];
	angle                       = [aConfig floatValueFromChildElementNamed:@"angle" parentElement:rootXMLElement];
	angleVariance               = [aConfig floatValueFromChildElementNamed:@"angleVariance" parentElement:rootXMLElement];
	gravity                     = [aConfig glkVector2FromChildElementNamed:@"gravity" parentElement:rootXMLElement];
    radialAcceleration          = [aConfig floatValueFromChildElementNamed:@"radialAcceleration" parentElement:rootXMLElement];
    tangentialAcceleration      = [aConfig floatValueFromChildElementNamed:@"tangentialAcceleration" parentElement:rootXMLElement];
	startColor                  = [aConfig glkVector4FromChildElementNamed:@"startColor" parentElement:rootXMLElement];
	startColorVariance          = [aConfig glkVector4FromChildElementNamed:@"startColorVariance" parentElement:rootXMLElement];
	finishColor                 = [aConfig glkVector4FromChildElementNamed:@"finishColor" parentElement:rootXMLElement];
	finishColorVariance         = [aConfig glkVector4FromChildElementNamed:@"finishColorVariance" parentElement:rootXMLElement];
	maxParticles                = [aConfig floatValueFromChildElementNamed:@"maxParticles" parentElement:rootXMLElement];
	startParticleSize           = [aConfig floatValueFromChildElementNamed:@"startParticleSize" parentElement:rootXMLElement];
	startParticleSizeVariance   = [aConfig floatValueFromChildElementNamed:@"startParticleSizeVariance" parentElement:rootXMLElement];
	finishParticleSize          = [aConfig floatValueFromChildElementNamed:@"finishParticleSize" parentElement:rootXMLElement];
	finishParticleSizeVariance  = [aConfig floatValueFromChildElementNamed:@"finishParticleSizeVariance" parentElement:rootXMLElement];
	duration                    = [aConfig floatValueFromChildElementNamed:@"duration" parentElement:rootXMLElement];
	blendFuncSource             = [aConfig intValueFromChildElementNamed:@"blendFuncSource" parentElement:rootXMLElement];
    blendFuncDestination        = [aConfig intValueFromChildElementNamed:@"blendFuncDestination" parentElement:rootXMLElement];
	
	// These paramters are used when you want to have the particles spinning around the source location
	maxRadius                   = [aConfig floatValueFromChildElementNamed:@"maxRadius" parentElement:rootXMLElement];
	maxRadiusVariance           = [aConfig floatValueFromChildElementNamed:@"maxRadiusVariance" parentElement:rootXMLElement];
	radiusSpeed                 = [aConfig floatValueFromChildElementNamed:@"radiusSpeed" parentElement:rootXMLElement];
	minRadius                   = [aConfig floatValueFromChildElementNamed:@"minRadius" parentElement:rootXMLElement];
	rotatePerSecond             = [aConfig floatValueFromChildElementNamed:@"rotatePerSecond" parentElement:rootXMLElement];
	rotatePerSecondVariance     = [aConfig floatValueFromChildElementNamed:@"rotatePerSecondVariance" parentElement:rootXMLElement];
    rotationStart               = [aConfig floatValueFromChildElementNamed:@"rotationStart" parentElement:rootXMLElement];
    rotationStartVariance       = [aConfig floatValueFromChildElementNamed:@"rotationStartVariation" parentElement:rootXMLElement];
    rotationEnd                 = [aConfig floatValueFromChildElementNamed:@"rotationEnd" parentElement:rootXMLElement];
    rotationEndVariance         = [aConfig floatValueFromChildElementNamed:@"rotationEndVariance" parentElement:rootXMLElement];
	
	// Calculate the emission rate
	emissionRate                = maxParticles / particleLifespan;

}

- (void)setupArrays {
	// Allocate the memory necessary for the particle emitter arrays
	particles = malloc( sizeof(Particle) * maxParticles );
    quads = calloc(sizeof(ParticleQuad), maxParticles);
    indices = calloc(sizeof(GLushort), maxParticles * 6);
    
    // Set up the indices for all particles. This provides an array of indices into the quads array that is used during 
    // rendering. As we are rendering quads there are six indices for each particle as each particle is made of two triangles
    // that are each defined by three vertices.
    for( int i=0;i< maxParticles;i++) {
		indices[i*6+0] = i*4+0;
		indices[i*6+1] = i*4+1;
		indices[i*6+2] = i*4+2;
		
		indices[i*6+5] = i*4+3;
		indices[i*6+4] = i*4+2;
		indices[i*6+3] = i*4+1;
	}
	
    // Set up texture coordinates for all particles as these will not change.
    for(int i=0; i<maxParticles; i++) {
        quads[i].bl.texture.x = 0;
        quads[i].bl.texture.y = 0;
        
        quads[i].br.texture.x = 1;
        quads[i].br.texture.y = 0;
		
        quads[i].tl.texture.x = 0;
        quads[i].tl.texture.y = 1;
        
        quads[i].tr.texture.x = 1;
        quads[i].tr.texture.y = 1;
	}
    
	// If one of the arrays cannot be allocated throw an assertion as this is bad
	NSAssert(particles && quads, @"ERROR - ParticleEmitter: Could not allocate arrays.");
    
	// Generate the vertices VBO
	glGenBuffers(1, &verticesID);
    glBindBuffer(GL_ARRAY_BUFFER, verticesID);
    glBufferData(GL_ARRAY_BUFFER, sizeof(ParticleQuad) * maxParticles, quads, GL_DYNAMIC_DRAW);
    glBindBuffer(GL_ARRAY_BUFFER, 0);
    
	// By default the particle emitter is active when created
	active = YES;
	
	// Set the particle count to zero
	particleCount = 0;
	
	// Reset the elapsed time
	elapsedTime = 0;	
}

@end

