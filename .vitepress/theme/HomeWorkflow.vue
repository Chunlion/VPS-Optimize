<script setup lang="ts">
import { computed } from 'vue'
import { useData, withBase } from 'vitepress'

interface WorkflowStep {
  icon: string
  title: string
  details: string
  link: string
}

interface WorkflowData {
  label: string
  steps: WorkflowStep[]
}

const { frontmatter } = useData()
const workflow = computed(() => frontmatter.value.workflow as WorkflowData)
</script>

<template>
  <section class="home-workflow" :aria-label="workflow.label">
    <div class="home-workflow__inner">
        <a v-for="step in workflow.steps" :key="step.title" class="home-workflow__step" :href="withBase(step.link)">
          <span class="home-workflow__icon" aria-hidden="true">
            <i :class="step.icon" />
          </span>
          <div>
            <h2>{{ step.title }}</h2>
            <p>{{ step.details }}</p>
          </div>
        </a>
    </div>
  </section>
</template>
