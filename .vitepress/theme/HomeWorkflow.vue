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
  <section class="home-workflow" aria-labelledby="workflow-title">
    <div class="home-workflow__inner">
      <h2 id="workflow-title">{{ workflow.label }}</h2>
      <ol class="home-workflow__list">
        <li v-for="(step, index) in workflow.steps" :key="step.title">
          <a class="home-workflow__step" :href="withBase(step.link)">
            <span class="home-workflow__number" aria-hidden="true">0{{ index + 1 }}</span>
            <div>
              <h3>{{ step.title }}</h3>
              <p>{{ step.details }}</p>
            </div>
            <i class="fa-solid fa-arrow-right" aria-hidden="true" />
          </a>
        </li>
      </ol>
    </div>
  </section>
</template>
