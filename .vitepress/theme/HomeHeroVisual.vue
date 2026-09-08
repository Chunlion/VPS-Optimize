<script setup lang="ts">
import { computed } from 'vue'
import { useData, withBase } from 'vitepress'

interface EntryGuide {
  title: string
  note: string
  link: string
  action: string
  modes: Array<{ name: string; description: string }>
}

const { frontmatter } = useData()
const guide = computed(() => frontmatter.value.hero.guide as EntryGuide)
</script>

<template>
  <section class="home-hero-visual" aria-labelledby="entry-guide-title">
    <div class="entry-guide__header">
      <span class="entry-guide__port" aria-hidden="true">443</span>
      <h2 id="entry-guide-title">{{ guide.title }}</h2>
    </div>
    <p class="entry-guide__note">{{ guide.note }}</p>
    <ul class="entry-guide__modes">
      <li v-for="(mode, index) in guide.modes" :key="mode.name">
        <span class="entry-guide__number" aria-hidden="true">0{{ index + 1 }}</span>
        <div><h3>{{ mode.name }}</h3><p>{{ mode.description }}</p></div>
      </li>
    </ul>
    <a class="entry-guide__link" :href="withBase(guide.link)">
      {{ guide.action }} <i class="fa-solid fa-arrow-right" aria-hidden="true" />
    </a>
  </section>
</template>
