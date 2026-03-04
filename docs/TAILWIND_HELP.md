# Tailwind CSS v4 Reference for Liquiditor

Liquiditor themes use **Tailwind CSS v4** via the `@tailwindcss/cli`.

- **Input file**: `themes/{THEME}/css/application.tailwind.css`
- **Output file**: `themes/{THEME}/assets/application.css`
- **Linked in layout**: `{{ 'application.css' | asset_url | stylesheet_tag }}`

The CSS watcher runs automatically in `bin/dev`. To rebuild manually:

```bash
# From the theme directory
yarn css
```

> **Purging**: Tailwind scans your `.liquid` template files for class names. Only classes that appear as complete strings will be included in the build. Never build class names from string concatenation in Liquid — use full class names or add them to the safelist.

---

## Custom Styles

Add custom utilities and components to `application.tailwind.css` using Tailwind v4 syntax:

```css
@import "tailwindcss";

@utility content-auto {
  content-visibility: auto;
}
```

Use custom utilities in templates like any built-in class:

```html
<div class="content-auto"><!-- ... --></div>
<div class="hover:content-auto"><!-- ... --></div>
```

To use CSS variables for dynamic values instead of `@apply`:

```css
button {
  background: var(--color-blue-500);
}
```

---

## Responsive Breakpoints

Apply utilities at specific screen sizes with breakpoint prefixes:

```html
<!-- justify-content: start on mobile, between on md+ -->
<div class="flex justify-start md:justify-between ...">
  <!-- ... -->
</div>

<!-- align-self: auto on mobile, end on md+ -->
<div class="self-auto md:self-end ...">
  <!-- ... -->
</div>

<!-- place-content: start on mobile, center on md+ -->
<div class="grid place-content-start md:place-content-center ...">
  <!-- ... -->
</div>

<!-- place-items: start on mobile, center on md+ -->
<div class="grid place-items-start md:place-items-center ...">
  <!-- ... -->
</div>

<!-- transition: none on mobile, all on md+ -->
<button class="transition-none md:transition-all ..."><!-- ... --></button>

<!-- box-sizing: content on mobile, border on md+ -->
<div class="box-content md:box-border ..."><!-- ... --></div>
```

---

## Flexbox

### flex-grow

```html
<!-- Allow one item to grow and fill available space -->
<div class="flex ...">
  <div class="size-14 flex-none ...">01</div>
  <div class="size-14 grow ...">02</div>
  <div class="size-14 flex-none ...">03</div>
</div>

<!-- Prevent a specific item from growing -->
<div class="flex ...">
  <div class="size-14 grow ...">01</div>
  <div class="size-14 grow-0 ...">02</div>
  <div class="size-14 grow ...">03</div>
</div>

<!-- Proportional growth with numbered utilities -->
<div class="flex ...">
  <div class="size-14 grow-3 ...">01</div>
  <div class="size-14 grow-7 ...">02</div>
  <div class="size-14 grow-3 ...">03</div>
</div>

<!-- Custom grow values -->
<div class="grow-[25vw] ..."><!-- ... --></div>
<div class="grow-(--my-grow) ..."><!-- ... --></div>

<!-- Responsive: grow on mobile, don't grow on md+ -->
<div class="grow md:grow-0 ..."><!-- ... --></div>
```

### flex-basis

```html
<!-- Fractional basis -->
<div class="flex flex-row">
  <div class="basis-1/3">01</div>
  <div class="basis-2/3">02</div>
</div>
```

### align-items

```html
<div class="flex items-start ...">
  <div class="py-4">01</div>
  <div class="py-12">02</div>
  <div class="py-8">03</div>
</div>
```

### align-self

```html
<div class="flex items-stretch ...">
  <div>01</div>
  <div class="self-start ...">02</div>
  <div>03</div>
</div>
```

### justify-content

```html
<div class="flex justify-start ...">
  <div>01</div>
  <div>02</div>
  <div>03</div>
</div>
```

### justify-self

```html
<div class="justify-self-start md:justify-self-end ..."><!-- ... --></div>
```

---

## Grid

### grid-column (col-start / col-end / col-span)

```html
<div class="grid grid-cols-6 gap-4">
  <div class="col-span-4 col-start-2 ...">01</div>
  <div class="col-start-1 col-end-3 ...">02</div>
  <div class="col-span-2 col-end-7 ...">03</div>
  <div class="col-start-1 col-end-7 ...">04</div>
</div>
```

### align-content

```html
<div class="grid h-56 grid-cols-3 content-start gap-4 ...">
  <div>01</div>
  <div>02</div>
  <div>03</div>
  <div>04</div>
  <div>05</div>
</div>
```

### place-content

```html
<!-- Pack items against the start of both axes -->
<div class="grid h-48 grid-cols-2 place-content-start gap-4 ...">
  <div>01</div>
  <div>02</div>
  <div>03</div>
  <div>04</div>
</div>
```

### place-items

```html
<!-- Align grid items to start on both axes -->
<div class="grid grid-cols-3 place-items-start gap-4 ...">
  <div>01</div>
  <div>02</div>
  <div>03</div>
  <div>04</div>
  <div>05</div>
  <div>06</div>
</div>
```

---

## Scroll Snap

```html
<div class="snap-x ...">
  <div class="snap-start ...">
    <img src="/img/vacation-01.jpg" />
  </div>
  <div class="snap-start ...">
    <img src="/img/vacation-02.jpg" />
  </div>
  <div class="snap-start ...">
    <img src="/img/vacation-03.jpg" />
  </div>
</div>
```

---

## Typography

### text-indent

```html
<!-- Positive indent -->
<p class="indent-8">...</p>

<!-- Negative indent -->
<p class="-indent-8">...</p>
```

### Lists

```html
<!-- Style an unstyled list -->
<ul class="list-inside list-disc">
  <li>One</li>
  <li>Two</li>
  <li>Three</li>
</ul>
```

---

## Backgrounds

### Conic Gradients

```html
<div class="size-24 rounded-full bg-conic from-blue-600 to-sky-400 to-50%"></div>
<div class="size-24 rounded-full bg-conic-180 from-indigo-600 via-indigo-50 to-indigo-600"></div>
<div class="size-24 rounded-full bg-conic/decreasing from-violet-700 via-lime-300 to-violet-700"></div>
```

---

## Pseudo-elements

### content (before/after)

```html
<!-- Add arrow after a link -->
<a class="text-blue-600 after:content-['_↗']" href="...">Link text</a>

<!-- Responsive content -->
<p class="before:content-['Mobile'] md:before:content-['Desktop'] ..."></p>
```

---

## Backdrop Filters

```html
<!-- backdrop-hue-rotate -->
<div class="bg-[url(/img/mountains.jpg)]">
  <div class="bg-white/30 backdrop-hue-rotate-90 ..."></div>
</div>

<!-- backdrop-contrast -->
<div class="bg-[url(/img/mountains.jpg)]">
  <div class="bg-white/30 backdrop-contrast-50 ..."></div>
</div>
<div class="bg-[url(/img/mountains.jpg)]">
  <div class="bg-white/30 backdrop-contrast-200 ..."></div>
</div>
```

---

## Transitions & Animations

### transition-property

```html
<button class="transition-none md:transition-all ..."><!-- ... --></button>
```

### transition-behavior (discrete properties like display)

```html
<!-- Fade out when hiding (uses @starting-style) -->
<button class="hidden transition-all transition-discrete not-peer-has-checked:opacity-0 peer-has-checked:block ...">
  I fade out
</button>
```

### @starting-style (initial render animations)

```html
<div popover id="my-popover" class="opacity-0 starting:open:opacity-0 ...">
  <!-- ... -->
</div>
```

---

## Miscellaneous Utilities

### isolation

```html
<div class="isolate md:isolation-auto ..."><!-- ... --></div>
```

### appearance

```html
<select class="appearance-auto md:appearance-none ...">
  <!-- ... -->
</select>
```

### forced-color-adjust

```html
<div class="forced-color-adjust-none md:forced-color-adjust-auto ...">
  <!-- ... -->
</div>
```

### max-block-size

```html
<div class="block-full max-block-1/2 ...">max-block-1/2</div>
<div class="block-full max-block-3/4 ...">max-block-3/4</div>
```

---

## Dynamic Classes in Liquid Templates

Because Tailwind scans templates statically, dynamic class construction will cause classes to be purged. Use a static map instead:

```liquid
{%- assign color_map = "blue:bg-blue-600 hover:bg-blue-500 text-white,red:bg-red-500 hover:bg-red-400 text-white,yellow:bg-yellow-300 hover:bg-yellow-400 text-black" -%}
```

Or safelist the classes in `application.tailwind.css`:

```css
@import "tailwindcss";

/* Safelist dynamically-used classes */
@source inline("bg-blue-600 bg-red-500 bg-yellow-300");
```
