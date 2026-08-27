-- 0014 borrowed the aspect ratio from the reference posters (3:4). The canvas
-- it has to fill is 9:16, and a wider page is drawn scaledToFill, so the sides
-- carrying the garments were cropped away. The layouts go upright with it.
update ai_model_config
   set params = jsonb_build_object(
           'lookbook', 'Compose an upright fashion lookbook page on a plain background. Place the '
               || 'person photo standing at full height down the middle so it fills the page top to '
               || 'bottom. Lay the garment cut-outs in one even row across the lower third. Under '
               || 'each garment print its name and the wear count exactly as given. Keep the person '
               || 'exactly as photographed: do not redraw, restyle, or replace the face.',
           'blisterGreen', 'Compose an upright toy blister pack on a pale green ridged card with a '
               || 'barcode at the top left and a hanging hole at the top centre, and the title in a '
               || 'serif face beneath them. Seal the person photo standing at full height in one '
               || 'tall clear compartment filling the middle of the card. Seal each garment cut-out '
               || 'in its own small clear compartment in a row along the bottom. Keep the person '
               || 'exactly as photographed: do not redraw, restyle, or replace the face.',
           'blisterCream', 'Compose an upright toy blister pack on a pale cream ridged card with a '
               || 'barcode at the top left and a hanging hole at the top centre, and the title in a '
               || 'bold condensed all-caps face beneath them. Seal the person photo standing at '
               || 'full height in one tall clear compartment filling the middle of the card. Seal '
               || 'each garment cut-out in its own small clear compartment in a row along the '
               || 'bottom. Keep the person exactly as photographed: do not redraw, restyle, or '
               || 'replace the face.',
           'resolution', '2K',
           'aspectRatio', '9:16'
       ),
       updated_by = 'migration',
       updated_at = now()
 where capability = 'outfit_template';
