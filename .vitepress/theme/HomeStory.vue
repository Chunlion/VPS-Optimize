<script setup lang="ts">
import { computed } from 'vue'
import { useData } from 'vitepress'

interface HomeStoryData {
  kicker: string
  title: string
  description: string
  principles: Array<{ icon: string; title: string; text: string }>
  terminalLabel: string
  terminalHeader: string
  terminalRows: Array<{ label: string; value: string }>
  primaryIcon: string
  primaryTitle: string
  primaryText: string
  secondaryIcon: string
  secondaryTitle: string
  secondaryText: string
}

const { frontmatter } = useData()
const story = computed(() => frontmatter.value.story as HomeStoryData)
</script>

<template>
  <section class="home-story" aria-labelledby="home-story-title">
    <div class="home-story__inner">
      <div class="home-story__copy">
        <p class="home-story__kicker">{{ story.kicker }}</p>
        <h2 id="home-story-title">{{ story.title }}</h2>
        <p class="home-story__description">{{ story.description }}</p>
        <ul class="home-story__principles">
          <li v-for="principle in story.principles" :key="principle.title">
            <i :class="principle.icon" aria-hidden="true" />
            <span>
              <strong>{{ principle.title }}</strong>
              <small>{{ principle.text }}</small>
            </span>
          </li>
        </ul>
      </div>

      <div class="home-story__terminal" :aria-label="story.terminalLabel">
        <div class="home-story__terminal-bar">
          <span>vps-optimize status</span>
          <span>●</span>
        </div>
        <div class="home-story__terminal-body">
          <div class="home-story__terminal-header">
            <span>{{ story.terminalHeader }}</span>
          </div>
          <div v-for="row in story.terminalRows" :key="row.label">
            <span>{{ row.label }}</span>
            <strong>{{ row.value }}</strong>
          </div>
        </div>
      </div>

      <div class="home-story__outcomes">
        <article>
          <i :class="story.primaryIcon" aria-hidden="true" />
          <div>
            <h3>{{ story.primaryTitle }}</h3>
            <p>{{ story.primaryText }}</p>
          </div>
        </article>
        <article>
          <i :class="story.secondaryIcon" aria-hidden="true" />
          <div>
            <h3>{{ story.secondaryTitle }}</h3>
            <p>{{ story.secondaryText }}</p>
          </div>
        </article>
      </div>
    </div>
  </section>
</template>
