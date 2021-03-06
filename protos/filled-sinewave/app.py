import pyglet

from pyglet.gl import *
from math import sin
from collections import Counter

subpix=2

window = pyglet.window.Window(width=320, height=200, resizable=True)

label = pyglet.text.Label('Hello, world',
                          font_name='Times New Roman',
                          font_size=36,
                          x=window.width // 2, y=window.height // 2,
                          anchor_x='center', anchor_y='center')


phase = 0.0
framecount = 0

fill_tbl = None

def anim(x):
    a = sin(x / 30.0 + phase) * 7.0
    b = sin(x / 45.0 + -phase*1.773) * 7.3
    return a + b


def update_anim(dt):
    global phase
    phase += dt


def draw_grid():
    glBegin(GL_LINES)
    glColor3f(0.3, 0.3, 0.3)
    for y in range(0, 200, 8):
        glVertex2f(0, y)
        glVertex2f(320, y)
    for x in range(0, 320, 8):
        glVertex2f(x, 0)
        glVertex2f(x, 200)
    glEnd()


def draw_1x1(x, y):
    glVertex2f(x, y)
#    pyglet.graphics.draw(4, pyglet.gl.GL_QUADS, ('v2f', [x, y, x+1, y, x+1, y+1, x, y+1]))
#    glBegin(GL_POINTS)
#    glVertex2f(x+1, y)
#    glVertex2f(x+1, y+1)
#    glVertex2f(x, y+1)
#    glEnd()

def draw_8x8(x, y):
    glBegin(GL_QUADS)
    glVertex2f(x, y)
    glVertex2f(x+7, y)
    glVertex2f(x+7, y+7)
    glVertex2f(x, y+7)
    glEnd()


def draw_block_cover(ypos):
    glEnable(GL_BLEND)
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
    glColor3f(0.5, 0.1, 0.05)
    for xi in range(0, 320 // 8):
        x = xi * 8
        y0 = (ypos[xi] // 8) * 8
        y1 = (ypos[xi + 1] // 8) * 8
        draw_8x8(x, y0)
        draw_8x8(x, y1)
    glDisable(GL_BLEND)


def draw_char(xp, yp, pix):
    glPointSize(2)
    glBegin(GL_POINTS)
    for y in range(0, 8):
        for x in range(0, 8):
            if pix[x + y * 8] != 0:
                glColor3f(0.5, 0.5, 0.5)
            else:
                glColor3f(0, 0, 0)
            draw_1x1(x + xp, y + yp)
    glEnd()

def draw_fills(ypos):
    global fill_tbl
    for xi in range(0, 320 // 8):
        x = xi * 8
        y0 = int((ypos[xi] * subpix))
        y1 = int((ypos[xi + 1] * subpix))

        yy0 = y0 & ~(8 * subpix - 1)
        yy1 = y1 & ~(8 * subpix - 1)

        y0 -= yy0
        y1 -= yy0

        chrs = fill_tbl[y0][y1 - y0 + 4 * subpix]

        draw_char(x, yy0 / subpix - 8, chrs[0])
        draw_char(x, yy0 / subpix, chrs[1])
        draw_char(x, yy0 / subpix + 8, chrs[2])
    glDisable(GL_BLEND)


@window.event
def on_draw():
    global phase, framecount
    # Flip y
    glMatrixMode(pyglet.gl.GL_PROJECTION)
    glLoadIdentity()
    glOrtho(0.0, 320, 200, 0.0, -1.0, 1.0)
    glMatrixMode(pyglet.gl.GL_MODELVIEW)
    glLoadIdentity()

    window.clear()

    ypos = [anim(x) + 100 for x in range(0, 320 + 8, 8)]

#    draw_block_cover(ypos)
    draw_grid()
    draw_fills(ypos)

#    pyglet.image.get_buffer_manager().get_color_buffer().save('frame_{:04d}.png'.format(framecount))
    framecount += 1
    return
    glColor3f(1, 1, 1)
    glBegin(GL_LINES)
    for xi in range(0, 320 // 8):
        x = xi * 8
        y0 = ypos[xi]
        y1 = ypos[xi + 1]
        glVertex2f(x, y0)
        glVertex2f(x + 8, y1)
    glEnd()


def mk8x8(yoffs, a, b, c):
    arr = [0 for x in range(8 * 8)]
    for y in range(0, 8):
        yy = (y + yoffs) * subpix
        for x in range(0, 8):
            xx = x * subpix
            if a * xx + b * yy + c < 0.0:
                arr[x + y * 8] = 0
            else:
                arr[x + y * 8] = 1
    return arr


def construct_fill_table():
    global fill_tbl, subpix
    x0 = 0
    x1 = 8 * subpix

    fill_tbl = [None for x in range(8 * subpix)]

    for y0 in range(0, 8 * subpix):
        fill_tbl[y0] = [None for x in range(0, 8 * subpix)]
        for yi1 in range(-4 * subpix, 4 * subpix):
            # ax + by + c = 0
            y1 = y0 + yi1
            a = -(y1 - y0)
            b = (x1 - x0)
            c = -(a * x0 + b * y0)
            fill_tbl[y0][yi1 + 4 * subpix] = [mk8x8(-8, a, b, c), mk8x8(0, a, b, c), mk8x8(8, a, b, c)]


def swap_idx(charset_idx, charidx_to_pix, pix, code):
    old_idx = charset_idx[pix]
    pix_a = charidx_to_pix[old_idx]
    pix_b = charidx_to_pix[code]

    charidx_to_pix[code] = pix_a
    charidx_to_pix[old_idx] = pix_b
    charset_idx[pix] = code
    charset_idx[pix_b] = old_idx


def save_table():
    global fill_tbl, subpix
    charset_idx = {}
    charidx_to_pix ={}
    charidx = 0
    for y0 in range(0, 8 * subpix):
        for y1 in range(0, 8 * subpix):
            chars = fill_tbl[y0][y1]
            for c in chars:
                if tuple(c) not in charset_idx:
                    charset_idx[tuple(c)] = charidx
                    charidx_to_pix[charidx] = tuple(c)
                    charidx += 1

    # swap chars so that the empty square is in the slot $20 (space) and the
    # fully filled block in block $a0 (filled block).  This is just to make it
    # look better if viewed without the charset enabled, ie., for explanations
    # on the blog.
    swap_idx(charset_idx, charidx_to_pix, tuple((0,)*64), 0x20)
    swap_idx(charset_idx, charidx_to_pix, tuple((1,)*64), 0xA0)

    with open("charset.inc", "wt") as fo:
        # write charset
        fo.write("charset:\n")
        for ci in range(0, charidx):
            c = charidx_to_pix[ci]
            fo.write("    // char ${:02x}\n".format(ci))
            for i in range(0,8):
                fo.write("    .byte %")
                for j in range(0, 8):
                    fo.write("{0}".format(c[i*8+j]))
                fo.write("\n")
        # write char indices
        fo.write("y0y1tbl:\n")
        for y1 in range(0, 8 * subpix):
            for y0 in range(0, 8 * subpix):
                chars = fill_tbl[y0][y1]
                fo.write("    .byte ")
                idx0 = charset_idx[tuple(chars[0])]
                idx1 = charset_idx[tuple(chars[1])]
                idx2 = charset_idx[tuple(chars[2])]
                idx3 = charset_idx[tuple((1,)*64)]
                fo.write("${:02x}, ${:02x}, ${:02x}, ${:02x}\n".format(idx0, idx1, idx2, idx3))

construct_fill_table()

unique_chars = Counter()
for i in fill_tbl:
    for chrs in fill_tbl:
        for c in chrs:
            unique_chars[str(c)] += 1

print ("unique chars: {0}", len(unique_chars))

save_table()

dt = 1/60.0
pyglet.clock.schedule_interval(update_anim, dt)
pyglet.app.run()

