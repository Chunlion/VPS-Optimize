<script setup lang="ts">
import { computed, ref } from 'vue'
import { useData } from 'vitepress'

const { frontmatter } = useData()
const install = computed(() => frontmatter.value.install)
const command = 'wget -qO vps.sh https://raw.githubusercontent.com/Chunlion/VPS-Optimize/main/dist/vps.sh && chmod +x vps.sh && ./vps.sh'
const state = ref<'idle' | 'copying' | 'copied' | 'error'>('idle')

async function copyCommand() {
  state.value = 'copying'
  try {
    await navigator.clipboard.writeText(command)
    state.value = 'copied'
  } catch {
    state.value = 'error'
  }
}
</script>

<template>
  <section class="home-install" :aria-label="install.title">
    <div class="home-install__bar">
      <span><i class="fa-solid fa-terminal" aria-hidden="true" /> {{ install.title }}</span>
      <button type="button" :disabled="state === 'copying'" @click="copyCommand">
        <i :class="state === 'copied' ? 'fa-solid fa-check' : 'fa-regular fa-copy'" aria-hidden="true" />
        {{ state === 'copying' ? install.copying : install.copy }}
      </button>
    </div>
    <pre tabindex="0" :aria-label="install.title"><code>{{ command }}</code></pre>
    <p class="home-install__note">{{ install.note }}</p>
    <p v-if="state === 'copied' || state === 'error'" class="home-install__feedback" :class="{ 'is-error': state === 'error' }" role="status">
      {{ state === 'copied' ? install.copied : install.error }}
    </p>
  </section>
</template>
