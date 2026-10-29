#version 460 core
#include <flutter/runtime_effect.glsl>
// ImageFilter supplies the size and rendered packed-video texture.
uniform vec2 u_size;
uniform sampler2D u_texture;
out vec4 fragColor;
void main() {
  vec2 uv = FlutterFragCoord().xy / u_size;
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
#endif
  // Left half = RGB, right half = the synchronized grayscale alpha matte.
  if (uv.x >= 0.5) { fragColor = vec4(0.0); return; }
  vec3 rgb = texture(u_texture, uv).rgb;
  float matte = texture(u_texture, vec2(uv.x + 0.5, uv.y)).r;
  // Remove compression-level near-black leakage; opaque cores remain opaque.
  float alpha = clamp((matte - 0.015) / 0.97, 0.0, 1.0);
  fragColor = vec4(rgb * alpha, alpha);
}
