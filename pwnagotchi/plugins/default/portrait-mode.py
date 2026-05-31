import logging
from PIL import Image, ImageFont, ImageDraw
import pwnagotchi.ui.fonts as fonts
import pwnagotchi.plugins as plugins

class PortraitMode(plugins.Plugin):
    __author__ = 'ex18a'
    __version__ = '1.0.0'
    __license__ = 'GPL3'
    __description__ = 'Overrides the core layout and plugin elements with extreme portrait coordinates.'

    def __init__(self):
        self.ready = False
        self.font_regular = '/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf'
        self.font_bold = '/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf'
        # This will secretly store the Landscape coordinates before we change them!
        self.original_state = {} 

    def on_loaded(self):
        logging.info("[Portrait Mode] Plugin loaded! Hijacking canvas dimensions...")

    def on_ui_setup(self, ui):
        try:
            # 1. Force Canvas variables into Portrait
            ui._width = 122
            ui._height = 250
            # 2. Rebuild the canvas
            ui._image = Image.new('1', (122, 250), 255)
            ui._draw = ImageDraw.Draw(ui._image)

            # Build fonts
            deja_9 = ImageFont.truetype(self.font_regular, 9)
            deja_10 = ImageFont.truetype(self.font_regular, 10)
            deja_11 = ImageFont.truetype(self.font_regular, 11)
            deja_bold_10 = ImageFont.truetype(self.font_bold, 10)
            deja_bold_11 = ImageFont.truetype(self.font_bold, 11)
            deja_bold_14 = ImageFont.truetype(self.font_bold, 14)
            deja_bold_35 = ImageFont.truetype(self.font_bold, 35)

            elements = ui._state._state

            # MASTER DICTIONARY
            portrait_layout = {
                'face': {'xy': (0, 85), 'font': deja_bold_35},
                'name': {'xy': (13, 25), 'font': deja_bold_14},
                'channel': {'xy': (5, 207), 'font': deja_10},
                'aps': {'xy': (40, 207), 'font': deja_10},
                'uptime': {'xy': (3, 3), 'font': deja_10},
                'friend_face': {'xy': (0, 200)},
                'friend_name': {'xy': (20, 130), 'font': deja_9},
                'shakes': {'xy': (3, 223), 'font': deja_11},
                'last_pwnd_name': {'xy': (3, 234), 'font': deja_11},
                'mode': {'xy': (93, 223), 'font': deja_bold_11},
                'status': {'xy': (4, 45), 'font': deja_10},
                'line1': {'xy': [0, 17, 125, 17]},
                'line2': {'xy': [0, 221, 125, 221]},

                # --- EXTRA PLUGINS ---
                'memtemp_header': {'xy': (32, 3), 'font': deja_10},
                'memtemp_data': {'xy': (32, 13), 'font': deja_10},
                'sugar_lbl': {'xy': (70, 3)},
                'sugar_val': {'xy': (90, 3)},
                'lifetime_train': {'xy': (5, 187), 'font': deja_10},
                'blind_val': {'xy': (5, 177)},
                'connection_status': {'xy': (60, 177)},
                'ip1': {'xy': (0, 140)},
            }

            # EXECUTE THE SWAP
            for key, styling in portrait_layout.items():
                if key in elements:
                    # Step A: Save the original Landscape state securely
                    if key not in self.original_state:
                        self.original_state[key] = {
                            'xy': elements[key].xy,
                            'font': getattr(elements[key], 'font', None)
                        }

                    # Step B: Apply your custom Portrait configuration
                    if 'xy' in styling:
                        elements[key].xy = styling['xy']
                    if 'font' in styling:
                        elements[key].font = styling['font']

            logging.info("[Portrait Mode] Core and Plugin overrides applied successfully.")

        except Exception as e:
            logging.error(f"[Portrait Mode] Failed to apply layout: {e}")

    def on_unload(self, ui):
        try:
            logging.info("[Portrait Mode] Plugin disabled. Reverting to Landscape...")

            # Restore variables to Landscape
            ui._width = 250
            ui._height = 122
            ui._image = Image.new('1', (250, 122), 255)
            ui._draw = ImageDraw.Draw(ui._image)

            elements = ui._state._state

            # Automatically put everything back exactly where we found it!
            for key, original in self.original_state.items():
                if key in elements:
                    elements[key].xy = original['xy']
                    if original['font'] is not None:
                        elements[key].font = original['font']

            # Wipe memory so it's fresh for next time
            self.original_state.clear()

            logging.info("[Portrait Mode] Restored perfect landscape layout.")

        except Exception as e:
            logging.error(f"[Portrait Mode] Failed to revert layout: {e}")
