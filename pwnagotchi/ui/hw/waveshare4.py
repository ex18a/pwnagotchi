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
        # Safely read orientation as a raw integer from config
        try:
            orientation = int(self.config.get('orientation', 0))
        except (ValueError, TypeError):
            orientation = 0

        if orientation in (90, 270):
            # --- PORTRAIT LAYOUT ---
            fonts.setup(10, 9, 10, 35, 25, 9)
            self._layout['width'] = 122
            self._layout['height'] = 250
            
            self._layout['face'] = (0, 45)
            self._layout['name'] = (5, 25)
            self._layout['channel'] = (0, 0)
            self._layout['aps'] = (30, 0)
            self._layout['uptime'] = (65, 0)
            self._layout['line1'] = [0, 15, 122, 15]
            self._layout['line2'] = [0, 230, 122, 230]
            self._layout['friend_face'] = (0, 200)
            self._layout['friend_name'] = (35, 202)
            self._layout['shakes'] = (0, 235)
            self._layout['mode'] = (90, 235)
            self._layout['status'] = {
                'pos': (5, 140),
                'font': fonts.status_font(fonts.Medium),
                'max': 18
            }
        else:
            # --- LANDSCAPE LAYOUT (0 or 180) ---
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
        logging.info("initializing waveshare v4 unified custom driver")
        from pwnagotchi.ui.hw.libs.waveshare.v4.epd2in13_V4 import EPD
        self._display = EPD()
        self._display.init()
        self._display.Clear(0xFF)

        # Base hardware frame buffer remains anchored at 122x250 portrait bytes
        self._display.displayPartBaseImage(self._display.getbuffer(Image.new('1', (122, 250), 0xFF)))

    def render(self, canvas):
        self._render_count += 1
        
        try:
            orientation = int(self.config.get('orientation', 0))
        except (ValueError, TypeError):
            orientation = 0

        # Process the incoming canvas dimensions and align them with the 122x250 panel
        if orientation == 0:
            # Landscape -> rotate 90 clockwise to package into 122x250 hardware space
            image = canvas.rotate(90, expand=True).convert('1')
        elif orientation == 180:
            # Inverted Landscape -> rotate 270 clockwise to fit 122x250 hardware space
            image = canvas.rotate(270, expand=True).convert('1')
        elif orientation == 270:
            # Inverted Portrait -> canvas is already 122x250, flip 180 upside down
            image = canvas.rotate(180).convert('1')
        else:
            # Standard Portrait (90) -> canvas is already 122x250, pass straight through
            image = canvas.convert('1')
            
        buf = self._display.getbuffer(image)

        if self._render_count % 1000 == 0:
            logging.info("Performing full screen refresh...")
            self._display.init()
            self._display.display(buf)
            self._display.displayPartBaseImage(buf) 
        else:
            self._display.displayPartial(buf)

    def clear(self):
        self._display.Clear(0xFF)
