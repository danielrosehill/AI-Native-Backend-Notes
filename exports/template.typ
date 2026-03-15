// AI-Native Backend Notes - Export Template

#let project(title: "", date: "", repo: "", body) = {
  set document(title: title)
  set page(
    paper: "a4",
    margin: (top: 2.5cm, bottom: 2.5cm, left: 2cm, right: 2cm),
    footer: context [
      #set text(8pt, fill: luma(130), font: "IBM Plex Sans")
      Content: Claude (Opus 4.6) #h(1fr) Generated: #date #h(1fr) Questions: Daniel Rosehill
      #v(2pt)
      Source Notebook: #link(repo)[#text(fill: luma(130))[#repo]]
      #h(1fr)
      #counter(page).display("1 / 1", both: true)
    ],
  )
  set text(font: "IBM Plex Sans", size: 10.5pt)
  set par(justify: true, leading: 0.65em)
  set heading(numbering: "1.1")

  // Inline code styling
  show raw.where(block: false): box.with(
    fill: luma(240),
    inset: (x: 4pt, y: 2pt),
    outset: (y: 2pt),
    radius: 3pt,
  )
  show raw.where(block: false): set text(font: "IBM Plex Mono", size: 9pt)

  // Code block styling
  show raw.where(block: true): block.with(
    fill: luma(245),
    inset: 10pt,
    radius: 4pt,
    width: 100%,
    stroke: 0.5pt + luma(210),
  )
  show raw.where(block: true): set text(font: "IBM Plex Mono", size: 8.5pt)
  show raw.where(block: true): set par(justify: false)

  // Title page
  v(3cm)
  align(center)[
    #text(26pt, weight: "bold")[#title]
    #v(1cm)
    #text(14pt, fill: luma(80))[AI-Native Backend Notes]
    #v(0.5cm)
    #text(12pt, fill: luma(100))[Generated: #date]
    #v(0.3cm)
    #text(10pt, fill: luma(120))[Daniel Rosehill]
  ]
  pagebreak()

  // Table of contents
  outline(indent: auto, depth: 2)
  pagebreak()

  body
}
