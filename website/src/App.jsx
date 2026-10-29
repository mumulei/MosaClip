import { useEffect, useLayoutEffect, useRef, useState } from "react";
import { SmoothCorners } from "@lisse/react";
import Typed from "typed.js";

const asset = path => `${import.meta.env.BASE_URL}${path.replace(/^\/+/, "")}`;
const repositoryURL = "https://github.com/mumulei/MosaClip";
const copy = {
  zh: {
    features: "功能",
    faq: "常见问题",
    get: "获取 MosaClip",
    title: ["复制的每一刻，", "都能随时回到手边。"],
    description: [
      "文字、链接、代码与灵感，复制即收藏。",
      "一个快捷键，找回片段，接着创造。",
    ],
    view: "产品展示",
    galleryLabel: "切换真实 App 截图",
    screens: ["工作区", "Markdown", "代码"],
    screenAlts: ["MosaClip 真实工作区：示例片段与 SVG 图片预览", "MosaClip 真实 Markdown 渲染预览", "MosaClip 真实代码语法高亮预览"],
    zoom: "放大查看截图",
    shortcutTitle: "按下快捷键，接着做你的事。",
    shortcutText: "不用在窗口间来回切换。唤起快捷面板，搜索片段，再粘贴回正在使用的应用。",
    shortcutSteps: ["唤起面板", "找到片段", "粘贴回去"],
    formatTitle: "每种内容，都有合适的样子。",
    formatText: "Markdown 看排版，代码看高亮，SVG 看图形。原文始终保留，复制的内容不走样。",
    formatTypes: ["文字", "链接", "图片", "代码", "Markdown", "SVG", "颜色", "文件"],
    privacyTitle: "只在你的 Mac，安心留下。",
    privacyText: "历史记录保存在本地。无需注册账号，敏感内容可以遮罩，也能排除不想捕获的应用。",
    privacyItems: ["本地存储", "敏感内容保护", "应用排除"],
    skip: "跳到主要内容",
    local: "本地存储",
    account: "无需账号",
    screenshot: "MosaClip 原生 macOS 工作区截图，展示多列内容卡片与图片详情",
    featureTitle: "留住片段，接着创造。",
    featureDescription: "让复制与粘贴之间，少一点打断。",
    questions: [
      {
        q: "MosaClip 支持哪些 Mac？",
        a: "MosaClip 需要 macOS 14（Sonoma）或更新版本。支持 Apple Silicon 与 Intel Mac；目前 QA 测试包仅提供 Apple Silicon 版本。",
      },
      {
        q: "我的剪贴板内容会上传吗？",
        a: "剪贴板历史保存在你的 Mac 上。你可以排除不希望被捕获的应用，敏感内容会遮罩显示。可选的本地 AI Agent 集成默认关闭，需要由你在设置中主动开启。",
      },
      {
        q: "现在可以下载正式版吗？",
        a: "0.5.0 已公开完整源码，可自行构建。正式安装包将在 Developer ID 签名与 Apple 公证完成后提供下载。",
      },
    ],
    closingTitle: "好内容，值得再用一次。",
    closingDescription: "给每一个复制的片段，一个随时可回的地方。",
    preview: "查看 MosaClip 源码",
    close: "关闭",
    dialogTitle: "MosaClip 0.5.0，现已开源。",
    dialogDescription: "MosaClip 0.5.0 已开源。查看完整源码、参与反馈或自行构建。",
    release:
      "现有测试包为 ad-hoc 签名，尚未完成 Developer ID 签名与 Apple 公证。正式版准备好后，这里会提供下载。",
    dialogCta: "前往 GitHub",
    requirements: "适用于 macOS 14 及更新版本",
    home: "MosaClip 首页",
    pageTitle: "MosaClip — 复制的每一刻，都能随时回到手边。",
    pageDescription:
      "MosaClip，你的 macOS 本地剪贴板工作区。留住文字、链接、代码与灵感，一个快捷键，随时回到手边。",
  },
  en: {
    features: "Features",
    faq: "FAQ",
    get: "Get MosaClip",
    title: ["Everything you copy,", "right where you need it."],
    description: [
      "Keep your words, links, code, and ideas close.",
      "One shortcut brings them back to your fingertips.",
    ],
    view: "Explore",
    galleryLabel: "Choose an actual app screenshot",
    screens: ["Workspace", "Markdown", "Code"],
    screenAlts: ["Actual MosaClip workspace with demo snippets and SVG preview", "Actual MosaClip Markdown rendering", "Actual MosaClip syntax-highlighted code preview"],
    zoom: "Enlarge screenshot",
    shortcutTitle: "One shortcut. Right back to work.",
    shortcutText: "Stay in the app you’re using. Open the quick panel, find a snippet, and paste it right back into your flow.",
    shortcutSteps: ["Open the panel", "Find a snippet", "Paste it back"],
    formatTitle: "The right view for every good bit.",
    formatText: "Rendered Markdown, highlighted code, and SVG previews. The original stays intact, ready to copy exactly as it was.",
    formatTypes: ["Text", "Links", "Images", "Code", "Markdown", "SVG", "Colors", "Files"],
    privacyTitle: "On your Mac. In your hands.",
    privacyText: "Your history is stored locally. No account needed. Mask sensitive content and exclude apps you don’t want to capture.",
    privacyItems: ["Local storage", "Sensitive content protection", "App exclusions"],
    skip: "Skip to content",
    local: "Stored locally",
    account: "No account needed",
    screenshot:
      "Actual MosaClip macOS workspace, showing multiple content cards and image details in the Chinese interface",
    featureTitle: "Keep the good bits. Keep creating.",
    featureDescription: "Less interruption between copy and paste.",
    questions: [
      {
        q: "Which Macs does MosaClip support?",
        a: "MosaClip requires macOS 14 (Sonoma) or later and supports Apple Silicon and Intel Macs. The current QA build is available for Apple Silicon only.",
      },
      {
        q: "Is my clipboard history uploaded?",
        a: "Your clipboard history is stored on your Mac. You can exclude specific apps, and sensitive content is masked. Optional local AI Agent integration is off by default and must be enabled by you in settings.",
      },
      {
        q: "Can I download a public release?",
        a: "MosaClip 0.5.0 source is public and can be built locally. Production downloads will follow Developer ID signing and Apple notarization.",
      },
    ],
    closingTitle: "Good things deserve another paste.",
    closingDescription: "Give everything you copy a place to come back to.",
    preview: "Explore the source",
    close: "Close",
    dialogTitle: "MosaClip 0.5.0 is open source.",
    dialogDescription:
      "MosaClip 0.5.0 is open source. Explore the complete code, share feedback, or build locally.",
    release:
      "Current test builds use ad-hoc signing and have not completed Developer ID signing or Apple notarization. Downloads will be available here when the public release is ready.",
    dialogCta: "View on GitHub",
    requirements: "Designed for macOS 14 and later",
    home: "MosaClip home",
    pageTitle: "MosaClip — Everything you copy, right where you need it.",
    pageDescription:
      "Your local clipboard workspace for macOS. Keep your words, links, code, and ideas close. One shortcut brings them back.",
  },
};
function Icon({ name, size = 18 }) {
  return (
    <img
      className="ui-icon"
      src={`${import.meta.env.BASE_URL}assets/icons/${name}.svg`}
      width={size}
      height={size}
      alt=""
      aria-hidden="true"
    />
  );
}
function Smooth({ as = "div", radius = 11, children, ...props }) {
  return (
    <SmoothCorners
      as={as}
      corners={{ radius, smoothing: 0.6 }}
      shadowStrategy="box-shadow"
      {...props}
    >
      {children}
    </SmoothCorners>
  );
}
// Scale the corner geometry with the rendered screenshot, including browser zoom.
function WorkspaceScreenshot({ alt, src = asset("/assets/mosaclip-workspace.png"), eager = false }) {
  const container = useRef(null);
  const [radius, setRadius] = useState(0);
  useLayoutEffect(() => {
    const element = container.current;
    // Ease the corner ratio from 3.2% on phones back to 2% at desktop width.
    const update = () => {
      const width = element.getBoundingClientRect().width;
      const mobileBlend = Math.max(0, Math.min(1, (900 - width) / 450));
      setRadius(width * (0.02 + 0.012 * mobileBlend));
    };
    update();
    const observer = new ResizeObserver(update);
    observer.observe(element);
    return () => observer.disconnect();
  }, []);
  return (
    <div ref={container} className="workspace-scale">
      <Smooth
        radius={radius}
        className="workspace-frame"
        style={{ borderRadius: radius }}
      >
        <img
          src={src}
          width="3024"
          height="1898"
          alt={alt}
          fetchPriority={eager ? "high" : "auto"}
          loading={eager ? "eager" : "lazy"}
        />
      </Smooth>
    </div>
  );
}
function useReducedMotion() {
  const [reduced, setReduced] = useState(() => matchMedia("(prefers-reduced-motion: reduce)").matches);
  useEffect(() => {
    const query = matchMedia("(prefers-reduced-motion: reduce)");
    const update = () => setReduced(query.matches);
    query.addEventListener("change", update);
    return () => query.removeEventListener("change", update);
  }, []);
  return reduced;
}

function TypingWord({ words, initial, reduced }) {
  const text = useRef(null);
  useEffect(() => {
    text.current.textContent = initial;
    if (reduced) return;
    const typing = new Typed(text.current, {
      // Typed.js inline pauses run on every pass, including after deletion.
      strings: words.map(word => `^800${word}`), startDelay: 3000,
      typeSpeed: 135, backSpeed: 90,
      backDelay: 3200, smartBackspace: false, loop: true,
      showCursor: true, cursorChar: "|", autoInsertCss: false, contentType: null,
    });
    const onVisibility = () => document.hidden ? typing.stop() : typing.start();
    document.addEventListener("visibilitychange", onVisibility);
    return () => { document.removeEventListener("visibilitychange", onVisibility); typing.destroy(); };
  }, [initial, words, reduced]);
  return <span className="typing-slot" aria-hidden="true">
    <span className="typing-live"><span ref={text}>{initial}</span></span>
  </span>;
}

function useShowcasePlayback(reduced, screenshotDialog) {
  const [screen, setScreen] = useState(0);
  const [hovered, setHovered] = useState(false);
  const [inView, setInView] = useState(false);
  const [hidden, setHidden] = useState(document.hidden);
  const [dialogOpen, setDialogOpen] = useState(false);
  const section = useRef(null);
  const progress = useRef(null);
  const elapsed = useRef(0);
  useEffect(() => {
    const observer = new IntersectionObserver(([entry]) => setInView(entry.isIntersecting), { threshold: .15 });
    observer.observe(section.current);
    const onVisibility = () => setHidden(document.hidden);
    const onClose = () => { setDialogOpen(false); setHovered(false); };
    const dialogElement = screenshotDialog.current;
    document.addEventListener("visibilitychange", onVisibility);
    dialogElement.addEventListener("close", onClose);
    return () => { observer.disconnect(); document.removeEventListener("visibilitychange", onVisibility); dialogElement.removeEventListener("close", onClose); };
  }, [screenshotDialog]);
  const stopped = hovered || !inView || hidden || reduced || dialogOpen;
  useEffect(() => {
    if (stopped) return;
    let frame;
    let last = performance.now();
    const tick = now => {
      elapsed.current += now - last;
      last = now;
      if (elapsed.current >= 5000) {
        elapsed.current = 0;
        setScreen(index => (index + 1) % 3);
      }
      progress.current?.style.setProperty("--playback-progress", Math.min(elapsed.current / 5000, 1));
      frame = requestAnimationFrame(tick);
    };
    frame = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(frame);
  }, [stopped]);
  const select = index => {
    setHovered(false);
    elapsed.current = 0;
    progress.current?.style.setProperty("--playback-progress", 0);
    setScreen(index);
  };
  return { screen, select, section, progress, setHovered, setDialogOpen };
}

function Action({
  as = "button",
  primary = false,
  small = false,
  children,
  ...props
}) {
  return (
    <Smooth
      as={as}
      autoEffects={false}
      radius={small ? 9 : 11}
      className={`button ${primary ? "primary" : "secondary"} ${small ? "small" : ""}`}
      {...props}
    >
      {children}
    </Smooth>
  );
}
// One observer for the page; keep native screenshot sizing independent of motion.
function useEntranceMotion() {
  useLayoutEffect(() => {
    const preference = window.matchMedia("(prefers-reduced-motion: reduce)");
    if (!window.IntersectionObserver) return;
    const groups = [
      [".header-inner > *", 55],
      [".hero > *", 80],
      [".workspace-section > *", 70],
      [".section-intro > *", 65],
      [".product-features > *", 65],
      [".faq > h2, .faq-list > details", 55],
      [".closing > *", 65],
      ["footer > *", 55],
    ];
    const elements = groups.flatMap(([selector, stagger]) =>
      [...document.querySelectorAll(selector)].map((element, index) => {
        element.style.setProperty("--entrance-delay", `${Math.min(index, 3) * stagger}ms`);
        return element;
      }),
    );
    const reveal = (element) => { element.dataset.entrance = "visible"; };
    const observer = new IntersectionObserver((entries) => {
      entries.forEach(({ target, isIntersecting }) => {
        if (isIntersecting) { reveal(target); observer.unobserve(target); }
      });
    }, { threshold: 0.08, rootMargin: "0px 0px -24px 0px" });
    const configure = () => {
      observer.disconnect();
      elements.forEach((element) => {
        if (preference.matches) reveal(element);
        else if (element.dataset.entrance !== "visible") {
          element.dataset.entrance = "pending";
          observer.observe(element);
        }
      });
    };
    // A keyboard user can reach content before its intersection callback.
    const onFocus = (event) => {
      const element = event.target.closest('[data-entrance="pending"]');
      if (element) { reveal(element); observer.unobserve(element); }
    };
    configure();
    preference.addEventListener("change", configure);
    document.addEventListener("focusin", onFocus);
    return () => {
      observer.disconnect();
      preference.removeEventListener("change", configure);
      document.removeEventListener("focusin", onFocus);
      elements.forEach((element) => { delete element.dataset.entrance; });
    };
  }, []);
}

function useInputModality() {
  useEffect(() => {
    const root = document.documentElement;
    const pointer = () => { root.dataset.inputMode = "pointer"; };
    const keyboard = event => {
      if (!event.metaKey && !event.ctrlKey && !event.altKey) root.dataset.inputMode = "keyboard";
    };
    pointer();
    window.addEventListener("pointerdown", pointer, true);
    window.addEventListener("keydown", keyboard, true);
    return () => {
      window.removeEventListener("pointerdown", pointer, true);
      window.removeEventListener("keydown", keyboard, true);
      delete root.dataset.inputMode;
    };
  }, []);
}

export function App() {
  useInputModality();
  useEntranceMotion();
  const [language, setLanguage] = useState(() => {
    try {
      return localStorage.getItem("mosaclip-site-language") === "en"
        ? "en"
        : "zh";
    } catch {
      return "zh";
    }
  });
  const [scrolled, setScrolled] = useState(() => window.scrollY > 16);
  const dialog = useRef(null);
  const screenshotDialog = useRef(null);
  const reduced = useReducedMotion();
  const playback = useShowcasePlayback(reduced, screenshotDialog);
  const { screen } = playback;
  const [theme, setTheme] = useState(() => {
    try { const value = localStorage.getItem("mosaclip-site-theme"); return ["light", "dark"].includes(value) ? value : "system"; }
    catch { return "system"; }
  });
  useEffect(() => {
    const system = matchMedia("(prefers-color-scheme: dark)");
    const apply = () => {
      const resolved = theme === "system" ? (system.matches ? "dark" : "light") : theme;
      document.documentElement.dataset.theme = resolved;
      document.documentElement.dataset.themePreference = theme;
      document.querySelector('meta[name="theme-color"]').content = resolved === "dark" ? "#181819" : "#f5f5f5";
    };
    apply();
    try { localStorage.setItem("mosaclip-site-theme", theme); } catch { /* Optional preference. */ }
    system.addEventListener("change", apply);
    return () => system.removeEventListener("change", apply);
  }, [theme]);
  useEffect(() => {
    [asset("/assets/workspace-markdown-clean.png"), asset("/assets/workspace-code-clean.png")].forEach(src => { const image = new Image(); image.src = src; });
  }, []);
  const screenSources = [asset("/assets/workspace-logo-clean.png"), asset("/assets/workspace-markdown-clean.png"), asset("/assets/workspace-code-clean.png")];
  const t = copy[language];
  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 16);
    window.addEventListener("scroll", onScroll, { passive: true });
    onScroll();
    return () => window.removeEventListener("scroll", onScroll);
  }, []);
  useEffect(() => {
    document.documentElement.lang = language === "zh" ? "zh-CN" : "en";
    document.title = t.pageTitle;
    document
      .querySelector('meta[name="description"]')
      .setAttribute("content", t.pageDescription);
    try {
      localStorage.setItem("mosaclip-site-language", language);
    } catch {
      /* Preferences are optional when storage is restricted. */
    }
  }, [language, t]);
  const openDownload = () => {
    dialog.current.showModal();
    dialog.current.focus({ preventScroll: true });
  };
  return (
    <>
      <a className="skip-link" href="#main-content">{t.skip}</a>
      <header className={`site-header ${scrolled ? "scrolled" : ""}`}>
        <div className="header-inner">
          <a href="#" className="brand" aria-label={t.home}>
            <img src={asset("/assets/mosaclip-icon.png")} alt="" />
            <span>MosaClip</span>
          </a>
          <nav aria-label={language === "zh" ? "主导航" : "Main navigation"}>
            <a href="#workspace">{t.view}</a>
            <a href="#features">{t.features}</a>
            <a href="#faq">{t.faq}</a>
          </nav>
          <div className="nav-right">
            <Smooth radius={10} className="language-switch theme-switch" autoEffects={false} role="group" aria-label={language === "zh" ? "外观主题" : "Appearance"}>
              {["system", "light", "dark"].map((mode, index) => {
                const label = (language === "zh" ? ["系统", "浅色", "暗色"] : ["System", "Light", "Dark"])[index];
                return <Smooth as="button" key={mode} radius={7} autoEffects={false} aria-label={label} title={label} aria-pressed={theme === mode} onClick={() => setTheme(mode)}><Icon name={["monitor", "sun", "moon"][index]} size={15} /></Smooth>;
              })}
            </Smooth>
            <Smooth
              radius={10}
              className="language-switch"
              autoEffects={false}
              as="div"
              role="group"
              aria-label={language === "zh" ? "页面语言" : "Page language"}
            >
              <Smooth
                as="button"
                autoEffects={false}
                radius={7}
                aria-label="切换为中文"
                aria-pressed={language === "zh"}
                onClick={() => setLanguage("zh")}
              >
                中
              </Smooth>
              <Smooth
                as="button"
                autoEffects={false}
                radius={7}
                aria-label="Switch to English"
                aria-pressed={language === "en"}
                onClick={() => setLanguage("en")}
              >
                EN
              </Smooth>
            </Smooth>
            {scrolled && (
              <div className="nav-download">
                <Action primary small onClick={openDownload}>
                  {t.get}
                  <Icon name="arrow-down" size={13} />
                </Action>
              </div>
            )}
          </div>
        </div>
      </header>
      <main id="main-content">
        <section className={`hero ${language === "en" ? "hero-en" : ""}`}>
          <h1 aria-label={t.title.join(language === "zh" ? "" : " ")}>
            <span aria-hidden="true" className="hero-title-part">{language === "zh" ? "复制的" : "Copy "}<TypingWord words={t.formatTypes} initial={language === "zh" ? "每一刻" : "anything"} reduced={reduced} />{language === "zh" ? "，" : ","}</span>
            {language === "zh" ? <wbr /> : <br />}
            <span aria-hidden="true" className="hero-title-part">{t.title[1]}</span>
          </h1>
          <p className="hero-description">
            {t.description[0]}
            <br className="mobile-break" /> {t.description[1]}
          </p>
          <div className="hero-actions">
            <Action primary onClick={openDownload}>
              <Icon name="apple" size={17} />
              {t.get}
              <Icon name="arrow-down" size={15} />
            </Action>
          </div>
          <p className="hero-meta">
            macOS 14+<span>·</span>
            {t.local}
            <span>·</span>
            {t.account}
          </p>
        </section>
        <section
          className="workspace-section"
          ref={playback.section}
          id="workspace"
          aria-label={t.view}
        >
          <div className="showcase-controls" role="group" aria-label={t.galleryLabel}>
            {t.screens.map((label, i) => <Smooth as="button" radius={9} autoEffects={false} key={i} aria-pressed={screen === i} onClick={() => playback.select(i)}>{label}{screen === i && <span key={screen} ref={playback.progress} className="tab-progress" aria-hidden="true" />}</Smooth>)}
          </div>
          <div className="stage-scale">
            <button className="screenshot-open" aria-label={t.zoom}
              onPointerEnter={event => { if (event.pointerType === "mouse") playback.setHovered(true); }}
              onPointerLeave={() => playback.setHovered(false)}
              onClick={() => {
                playback.setDialogOpen(true);
                screenshotDialog.current.showModal();
                screenshotDialog.current.focus({ preventScroll: true });
              }}>
              <WorkspaceScreenshot alt={t.screenAlts[screen]} src={screenSources[screen]} eager />
              <span className="zoom-cue" aria-hidden="true"><Icon name="plus" size={18} /></span>
            </button>
          </div>
        </section>
        <section className="features" id="features">
          <div className="section-intro">
            <h2>{t.featureTitle}</h2>
            <p>{t.featureDescription}</p>
          </div>
          <div className="product-features">
            <Smooth radius={24} className="shortcut-feature" autoEffects={false}>
              <div className="feature-copy">
                <h3><Icon name="command" size={23} />{t.shortcutTitle}</h3>
                <p>{t.shortcutText}</p>
              </div>
              <div className="shortcut-art">
                <div className="key-row" aria-label="Command Shift V">
                  <kbd>⌘</kbd><kbd>⇧</kbd><kbd>V</kbd>
                </div>
                <ol className="shortcut-steps">{t.shortcutSteps.map((step,i) => <li key={step}><span>{i + 1}</span>{step}</li>)}</ol>
              </div>
            </Smooth>
            <Smooth radius={24} className="format-feature" autoEffects={false}>
              <div className="feature-copy"><h3><Icon name="layers" size={23} />{t.formatTitle}</h3><p>{t.formatText}</p></div>
              <div className="format-types">{t.formatTypes.map((type,i) => <span key={type}><Icon name={["file-text","link","image","code","file-text","code","palette","files"][i]} size={17} />{type}</span>)}</div>
            </Smooth>
            <Smooth radius={24} className="privacy-feature" autoEffects={false}>
              <div className="feature-copy"><h3><Icon name="shield-check" size={23} />{t.privacyTitle}</h3><p>{t.privacyText}</p></div>
              <div className="local-art" aria-hidden="true"><div className="local-device"><div className="local-screen"><img src={asset("/assets/mosaclip-icon.png")} alt="" /></div><div className="local-base"/></div></div>
              <ul className="privacy-checks">{t.privacyItems.map((item,i) => <li key={item}><Icon name={["hard-drive","lock-keyhole","app-window-x"][i]} size={16} />{item}</li>)}</ul>
            </Smooth>
          </div>
        </section>
        <section className="faq" id="faq">
          <h2>{t.faq}</h2>
          <div className="faq-list">
            {t.questions.map((q, i) => (
              <details key={i}>
                <summary>
                  {q.q}
                  <Icon name="plus" size={18} />
                </summary>
                <p>{q.a}</p>
              </details>
            ))}
          </div>
        </section>
        <section className="closing">
          <img src={asset("/assets/mosaclip-icon.png")} alt="" />
          <h2>{t.closingTitle}</h2>
          <p>{t.closingDescription}</p>
          <Action primary onClick={openDownload}>
            {t.preview}
            <Icon name="arrow-up-right" size={15} />
          </Action>
        </section>
      </main>
      <footer>
        <a className="brand" href="#">
          <img src={asset("/assets/mosaclip-icon.png")} alt="" />
          <span>MosaClip</span>
        </a>
        <span>© {new Date().getFullYear()} MosaClip · <a href={repositoryURL}>GitHub</a> · <a href="https://github.com/lifedever/PasteMemo-app">PasteMemo</a></span>
      </footer>
      <dialog ref={screenshotDialog} tabIndex={-1} className="image-dialog" aria-label={t.zoom} onClick={event => {if(event.target === screenshotDialog.current) screenshotDialog.current.close();}}>
        <form method="dialog"><button className="image-close" aria-label={t.close}><Icon name="x" size={22} /></button></form>
        <img src={screenSources[screen]} alt={t.screenAlts[screen]} width="3024" height="1898" />
      </dialog>
      <dialog
        ref={dialog}
        tabIndex={-1}
        className="download-dialog"
        aria-labelledby="download-title"
        onClick={(event) => {
          if (event.target === dialog.current) dialog.current.close();
        }}
      >
        <Smooth radius={24} className="dialog-body">
          <form method="dialog">
            <Smooth
              as="button"
              autoEffects={false}
              radius={10}
              className="dialog-close"
              aria-label={t.close}
            >
              <Icon name="x" size={19} />
            </Smooth>
          </form>
          <img src={asset("/assets/mosaclip-icon.png")} className="dialog-icon" alt="" />
          <h2 id="download-title">{t.dialogTitle}</h2>
          <p>{t.dialogDescription}</p>
          <Smooth radius={12} className="release-note">
            <Icon name="info" size={18} />
            <p>{t.release}</p>
          </Smooth>
          <Action as="a" primary href={repositoryURL} target="_blank" rel="noopener noreferrer">
            {t.dialogCta}
            <Icon name="arrow-up-right" size={15} />
          </Action>
          <p className="dialog-requirements">{t.requirements}</p>
        </Smooth>
      </dialog>
    </>
  );
}
