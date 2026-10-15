#include "WGABI.h"
#include <assert.h>
#include <stdio.h>
int main(void) {
    assert(WGIntegerWidth("I") == 4);
    assert(WGIntegerWidth("i") == 4);
    assert(WGIntegerWidth("q") == 8);
    assert(WGIntegerWidth("Q") == 8);
    assert(WGIntegerWidth("rnQ") == 8);
    assert(WGIntegerWidth("@") == 0);
    assert(WGIntegerWidth(NULL) == 0);
    assert(WGIntegerWidth("") == 0);
    assert(WGIsBool("B"));
    assert(WGIsBool("c"));
    assert(!WGIsBool(""));
    assert(!WGIsBool("I"));
    assert(!WGIsBool("Bextra"));
    // Count result and section argument must be checked independently.
    assert(WGIntegerWidth("I") != WGIntegerWidth("Q"));
    // The reverse lookup in the supplied sample returns a native scalar row.
    assert(WGIntegerWidth("q") == sizeof(long));
    puts("ABI encoding helper tests: PASS (15 assertions)");
    return 0;
}
