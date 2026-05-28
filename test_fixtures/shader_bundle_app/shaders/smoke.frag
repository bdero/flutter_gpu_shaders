#version 460 core

#include <shared_color.glsl>

out vec4 frag_color;

void main() {
  frag_color = sharedColor();
}
