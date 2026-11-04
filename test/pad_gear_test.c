/* The right stick's gear sectors (hud.h hud_gear_at). Exits nonzero on a wrong gear.
 * build: cc -Isrc -Isrc/phys test/pad_gear_test.c -o /tmp/pad_gear_test && /tmp/pad_gear_test */
#include <assert.h>
#include <stdio.h>
#include "hud.h"

int main(void) {
  const float d = 0.7f, dead = 0.5f;
  assert(hud_gear_at(0, 0, dead, 6) == 0);
  assert(hud_gear_at(0.3f, -0.3f, dead, 6) == 0); /* inside the dead zone */
  assert(hud_gear_at(-d, -d, dead, 4) == 1);
  assert(hud_gear_at(-d, d, dead, 4) == 2);
  assert(hud_gear_at(d, -d, dead, 4) == 3);
  assert(hud_gear_at(d, d, dead, 4) == 4);
  for (int gears = 5; gears <= 6; ++gears) {
    assert(hud_gear_at(-d, -d, dead, gears) == 1);
    assert(hud_gear_at(-d, d, dead, gears) == 2);
    assert(hud_gear_at(0, -1, dead, gears) == 3);
    assert(hud_gear_at(0, 1, dead, gears) == 4);
    assert(hud_gear_at(d, -d, dead, gears) == 5);
    assert(hud_gear_at(d, d, dead, gears) == 6);
  }
  puts("ok");
  return 0;
}
