const gallery = document.querySelector("[data-gallery]");

if (gallery) {
  const picture = gallery.querySelector("picture");
  const image = picture.querySelector("img");
  const darkSource = picture.querySelector("source");
  const caption = document.querySelector("#music-caption");
  const description = document.querySelector("#music-description");
  const mediaFolder = image.getAttribute("src").replace(/[^/]+$/, "");
  const views = {
    drums: {
      caption: "Drum machine / find your groove",
      description: "Eight tracks, grooves to get you started, and similar sounds ready to swap in.",
      alt: "Clap Studio’s eight-track drum machine with a sixteen-step beat beneath the sample library.",
    },
    melody: {
      caption: "Melody / follow an idea",
      description: "Four melody tracks with a piano roll. Draw notes or bring a MIDI file.",
      alt: "Clap Studio’s melody editor with a piano keyboard, notes, and sample tracks.",
    },
    ensemble: {
      caption: "Drums + melody / the sketch starts here",
      description: "An eight-track drum machine and four melody tracks, together at the same project tempo.",
      alt: "The drum machine and melody editor open together beneath Clap Studio’s sample library.",
    },
  };
  const buttons = gallery.querySelectorAll("button[data-view]");
  gallery.querySelector(".gallery-controls").hidden = false;

  for (const button of buttons) {
    button.addEventListener("click", () => {
      const name = button.dataset.view;
      const view = views[name];
      if (!view) return;
      darkSource.srcset = `${mediaFolder}${name}-dark.png`;
      image.src = `${mediaFolder}${name}-light.png`;
      image.alt = view.alt;
      caption.textContent = view.caption;
      description.textContent = view.description;
      for (const choice of buttons) {
        choice.setAttribute("aria-pressed", String(choice === button));
      }
    });
  }
}
