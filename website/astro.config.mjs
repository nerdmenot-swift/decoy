// The Decoy documentation site — decoy.nerdmenot.in
//
// Starlight owns `src/content/docs/**` and nothing else. The landing page and the
// story pages are plain Astro routes with their own layout, because a docs framework's
// default shell is the fastest way to make a project look like every other project.
// What Starlight is here for is the part it genuinely does better than a bespoke build:
// sidebar, search, keyboard nav, heading anchors and a11y on the reference pages.
import { defineConfig } from 'astro/config'
import starlight from '@astrojs/starlight'

export default defineConfig({
  site: 'https://decoy.nerdmenot.in',
  integrations: [
    starlight({
      title: 'Decoy',
      description:
        'Seeded fake data for Swift, with provenance. Every value traces to a licensed, ' +
        'pinned source — and where it cannot, the corpus says so rather than guessing.',
      logo: { src: './src/assets/icon.svg', alt: 'Decoy', replacesTitle: false },
      favicon: '/icon.svg',
      customCss: ['./src/styles/theme.css'],
      // Code reads as a terminal in both site themes. A light syntax theme on warm paper
      // washes out to near-invisible, and switching themes mid-scroll is worse than
      // committing to one.
      expressiveCode: {
        themes: ['github-dark'],
        styleOverrides: {
          borderRadius: '3px',
          borderColor: 'transparent',
          codeFontFamily: 'var(--decoy-mono)',
        },
      },
      components: {
        // The two loudest Starlight tells: its header lockup and its theme dropdown.
        Header: './src/components/Header.astro',
        PageTitle: './src/components/PageTitle.astro',
      },
      social: [
        { icon: 'github', label: 'GitHub', href: 'https://github.com/NerdMeNot/decoy' },
      ],
      editLink: { baseUrl: 'https://github.com/NerdMeNot/decoy/edit/main/website/' },
      lastUpdated: true,
      pagination: true,
      head: [
        { tag: 'link', attrs: { rel: 'preconnect', href: 'https://fonts.googleapis.com' } },
        {
          tag: 'link',
          attrs: { rel: 'preconnect', href: 'https://fonts.gstatic.com', crossorigin: true },
        },
        {
          tag: 'link',
          attrs: {
            rel: 'stylesheet',
            href:
              'https://fonts.googleapis.com/css2?' +
              'family=Public+Sans:wght@400;500;600;700&' +
              'family=IBM+Plex+Mono:wght@400;500;600&display=swap',
          },
        },
      ],
      sidebar: [
        {
          label: 'Start here',
          items: [
            { slug: 'start/install' },
            { slug: 'start/first-fixtures' },
            { slug: 'start/forges' },
          ],
        },
        {
          label: 'The ideas',
          items: [
            { slug: 'ideas/determinism' },
            { slug: 'ideas/provenance' },
            { slug: 'ideas/coherence' },
            { slug: 'ideas/locales' },
            { slug: 'ideas/refusals' },
          ],
        },
        {
          label: 'Having fun with it',
          items: [
            { slug: 'fun/invented' },
            { slug: 'fun/real-world' },
            { slug: 'fun/seeding-a-database' },
          ],
        },
        {
          label: 'Reference',
          items: [
            { slug: 'reference/namespaces' },
            { slug: 'reference/locale-matrix' },
            { slug: 'reference/sources' },
            { slug: 'reference/cli' },
            { slug: 'reference/corpus-format' },
          ],
        },
      ],
    }),
  ],
})
