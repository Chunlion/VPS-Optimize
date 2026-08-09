<script setup lang="ts">
import { computed } from 'vue'
import { useData } from 'vitepress'

interface WorkflowStep {
  icon: string
  title: string
  details: string
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
      <template v-for="(step, index) in workflow.steps" :key="step.title">
        <article class="home-workflow__step">
          <span class="home-workflow__icon" aria-hidden="true">
            <i :class="step.icon" />
          </span>
          <div>
            <h2>{{ step.title }}</h2>
            <p>{{ step.details }}</p>
          </div>
        </article>
        <i
          v-if="index < workflow.steps.length - 1"
          class="home-workflow__arrow fa-solid fa-arrow-right"
          aria-hidden="true"
        />
      </template>
    </div>
  </section>
</template>
