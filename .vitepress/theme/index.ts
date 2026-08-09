import { defineComponent, h } from 'vue'
import { useData } from 'vitepress'
import DefaultTheme from 'vitepress/theme'
import HomeHeroVisual from './HomeHeroVisual.vue'
import HomeStory from './HomeStory.vue'
import HomeWorkflow from './HomeWorkflow.vue'
import '@fortawesome/fontawesome-free/css/all.min.css'
import '@fontsource-variable/inter'
import '@fontsource-variable/noto-sans-sc'
import './style.css'
import './custom.css'

export default {
  extends: DefaultTheme,
  Layout: defineComponent({
    setup() {
      const { frontmatter } = useData()

      return () => h(DefaultTheme.Layout, null, {
        'home-hero-info-before': () => frontmatter.value.hero?.eyebrow
          ? h('p', { class: 'home-eyebrow' }, frontmatter.value.hero.eyebrow)
          : null,
        'home-hero-image': () => frontmatter.value.hero?.image
          ? h(HomeHeroVisual)
          : null,
        'home-features-before': () => frontmatter.value.workflow
          ? h(HomeWorkflow)
          : null,
        'home-features-after': () => frontmatter.value.story
          ? h(HomeStory)
          : null
      })
    }
  })
}
