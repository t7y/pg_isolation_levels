import React from 'react'

export default {
  logo: <span style={{ fontWeight: 700 }}>PostgreSQL Isolation Levels Lab</span>,
  project: {
    link: 'https://github.com/'
  },
  docsRepositoryBase: 'https://github.com/',
  editLink: {
    component: null
  },
  feedback: {
    content: null
  },
  footer: {
    content: (
      <span>
        PostgreSQL Isolation Levels Lab — a hands-on sandbox for transaction isolation.
      </span>
    )
  },
  useNextSeoProps() {
    return { titleTemplate: '%s – PG Isolation Lab' }
  },
  head: (
    <>
      <meta name="viewport" content="width=device-width, initial-scale=1.0" />
      <meta
        name="description"
        content="A hands-on lab for exploring PostgreSQL transaction isolation levels: Read Committed, Repeatable Read, and Serializable, and the anomalies each does and does not prevent."
      />
      <link rel="icon" href="/favicon.ico" sizes="any" />
    </>
  ),
  theme: 'dark',
  primaryHue: 145,
  sidebar: {
    defaultMenuCollapseLevel: 1,
    toggleButton: true
  },
  toc: {
    backToTop: true
  }
}
