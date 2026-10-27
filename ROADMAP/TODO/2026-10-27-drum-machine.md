# Drum machine

I don't like the new label we added above each track in the drum machine that says "Bar N". I liked how compact the view was before. Let's get rid of this extra label.

I also don't like the slider we added to show that the area can scroll. Please find a more visually pleasing and native way to communicate to the user that. Take inspiration from the Ableton Live (https://www.ableton.com/en/live/what-is-live/) UI.

Make sure that the `Length [ n  ] bars` input:
- is a number input that the user can increase/decrease with a click or arrow keys: currently you can only type a value
- when changing from singular to plural the UI doesn't shift: `Length [1] bar` vs `Length [2] bars`
