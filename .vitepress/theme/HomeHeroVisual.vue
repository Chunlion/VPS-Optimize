<script setup lang="ts">
import { computed } from 'vue'
import { useData, withBase } from 'vitepress'

interface HomeHeroImage {
  light: string
  dark: string
  alt: string
  caption: string
}

const { frontmatter } = useData()
const image = computed(() => frontmatter.value.hero.image as HomeHeroImage)
</script>

<template>
  <figure class="home-hero-visual">
    <img class="image-src light" :src="withBase(image.light)" :alt="image.alt">
    <img class="image-src dark" :src="withBase(image.dark)" :alt="image.alt">
    <figcaption>{{ image.caption }}</figcaption>
  </figure>
</template>
