// Capacity bars: every widget block whose value is a percentage gets a fill bar (custom.css).
// The colour follows the block's highlight level (good / warn / danger, set in services.yaml).
(() => {
  const apply = () => {
    document.querySelectorAll(".service-block").forEach((block) => {
      const value = block.querySelector(".service-block-value");
      const m = value && value.textContent.trim().match(/^(\d+(?:[.,]\d+)?)\s*%$/);
      if (!m) {
        block.classList.remove("pct-bar");
        return;
      }
      const pct = Math.max(0, Math.min(100, parseFloat(m[1].replace(",", "."))));
      block.style.setProperty("--pct", `${pct}%`);
      block.classList.add("pct-bar");
    });
  };
  // Values arrive and refresh after load; only text/children are watched, so applying never loops.
  new MutationObserver(apply).observe(document.body, { childList: true, subtree: true, characterData: true });
  apply();
})();
