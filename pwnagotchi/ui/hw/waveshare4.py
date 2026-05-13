import logging

import pwnagotchi.ui.fonts as fonts
from pwnagotchi.ui.hw.base import DisplayImpl
from PIL import Image

class WaveshareV4(DisplayImpl):
    def __init__(self, config):
        super(WaveshareV4, self).__init__(config, 'waveshare_4')
        self._display = None
        self._render_count = 0

    def layout(self):
        fonts.setup(10, 8, 10, 35, 25, 9)
        self._layout['width'] = 250
        self._layout['height'] = 122
        self._layout['face'] = (0, 40)
        self._layout['name'] = (5, 20)
        self._layout['channel'] = (0, 0)
        self._layout['aps'] = (28, 0)
        self._layout['uptime'] = (185, 0)
        self._layout['line1'] = [0, 14, 250, 14]
        self._layout['line2'] = [0, 108, 250, 108]
        self._layout['friend_face'] = (0, 92)
        self._layout['friend_name'] = (40, 94)
        self._layout['shakes'] = (0, 109)
        self._layout['mode'] = (225, 109)
        self._layout['status'] = {
            'pos': (125, 20),
            'font': fonts.status_font(fonts.Medium),
            'max': 20
        }

        return self._layout

    def initialize(self):
        logging.info("initializing waveshare v4 with partial refresh")
        from pwnagotchi.ui.hw.libs.waveshare.v4.epd2in13_V4 import EPD
        self._display = EPD()

        # Initial full refresh to clear the screen
        self._display.init()
        self._display.Clear(0xFF)

        # V4 specifically needs this to "anchor" the first frame for partial updates
        self._display.displayPartBaseImage(self._display.getbuffer(Image.new('1', (250, 122), 0xFF)))

    def render(self, canvas):
        self._render_count += 1
        image = canvas.rotate(0, expand=True).convert('1')
        buf = self._display.getbuffer(image)

        # Every 3000 frames, do a full refresh to clear ghosting
        if self._render_count % 3000 == 0:
            logging.info("Performing full screen refresh to clear ghosting...")
            self._display.init() # Re-init for full mode
            self._display.display(buf)
            # Re-establish the partial base so the next frame doesn't go white
            self._display.displayPartBaseImage(buf) 
        else:
            # Standard smooth partial update
            self._display.displayPartial(buf)

    def clear(self):
        self._display.Clear(0xFF)
