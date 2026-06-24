document.addEventListener('DOMContentLoaded', () => {
    // ----------------------------------------------------
    // 1. 聊天模拟器逻辑 (Chat Simulator)
    // ----------------------------------------------------
    const chatBody = document.getElementById('simulator-chat-body');
    const inputField = document.getElementById('simulator-input-field');
    const peerName = document.getElementById('simulator-peer-name');

    // 辅助延时函数
    const delay = ms => new Promise(resolve => setTimeout(resolve, ms));

    // 模拟输入框打字效果
    async function typeInputText(text, speed = 80) {
        inputField.textContent = '';
        inputField.classList.add('typing');
        for (let i = 0; i < text.length; i++) {
            inputField.textContent += text[i];
            await delay(speed);
        }
        inputField.classList.remove('typing');
    }

    // 清空输入框并变灰
    function setInputPlaceholder(text) {
        inputField.textContent = text;
        inputField.classList.remove('typing');
    }

    // 插入消息气泡
    function appendMessage(text, isSent = false) {
        const bubble = document.createElement('div');
        bubble.className = `message-bubble ${isSent ? 'message-sent' : 'message-received'}`;
        bubble.textContent = text;
        chatBody.appendChild(bubble);
        scrollToBottom();
        return bubble;
    }

    // 插入分割线
    function appendSeparator(text) {
        const separator = document.createElement('div');
        separator.className = 'chat-separator';
        separator.textContent = text;
        chatBody.appendChild(separator);
        scrollToBottom();
    }

    // 滚动到底部
    function scrollToBottom() {
        chatBody.scrollTop = chatBody.scrollHeight;
    }

    // 插入文件传输气泡并模拟进度
    async function appendFileTransfer(fileName, fileSize, duration = 2000) {
        const bubble = document.createElement('div');
        bubble.className = 'message-bubble message-sent';
        bubble.style.width = '280px';
        bubble.style.padding = '0.5rem';

        const transferCard = document.createElement('div');
        transferCard.className = 'transfer-card';

        // 构造文件图标和详情
        transferCard.innerHTML = `
            <div class="transfer-info">
                <div class="file-icon">
                    <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2">
                        <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/>
                        <path d="M14 2v6h6M16 13H8M16 17H8M10 9H8"/>
                    </svg>
                </div>
                <div class="file-details">
                    <span class="file-name">${fileName}</span>
                    <span class="file-size">${fileSize}</span>
                </div>
            </div>
            <div class="progress-bar-container">
                <div class="progress-bar-fill" style="width: 0%"></div>
            </div>
            <span class="transfer-status-text">准备发送...</span>
        `;

        bubble.appendChild(transferCard);
        chatBody.appendChild(bubble);
        scrollToBottom();

        const progressFill = transferCard.querySelector('.progress-bar-fill');
        const statusText = transferCard.querySelector('.transfer-status-text');

        // 模拟进度条增长
        statusText.textContent = '正在发送...';
        const steps = 20;
        const stepDelay = duration / steps;
        for (let i = 1; i <= steps; i++) {
            await delay(stepDelay);
            const percent = Math.floor((i / steps) * 100);
            progressFill.style.width = `${percent}%`;
        }

        statusText.textContent = '已发送';
        statusText.style.color = '#10b981'; // 变成亮绿色
        scrollToBottom();
        await delay(300);
    }

    // 插入配对请求卡片
    async function appendPairingCard() {
        const card = document.createElement('div');
        card.className = 'message-bubble message-received';
        card.style.width = '280px';
        card.style.padding = '1rem';
        card.innerHTML = `
            <div style="font-weight:600; margin-bottom:0.5rem; display:flex; align-items:center; gap:0.4rem;">
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#1fa37a" stroke-width="2">
                    <rect x="3" y="11" width="18" height="11" rx="2" ry="2"/>
                    <path d="M7 11V7a5 5 0 0 1 10 0v4"/>
                </svg>
                安全配对请求
            </div>
            <p style="font-size:0.8rem; color:var(--text-secondary); margin-bottom:0.8rem;">首次连接，请确认 6 位安全校验码：</p>
            <div style="font-family: monospace; font-size:1.5rem; font-weight:700; color:var(--accent-light); text-align:center; background:rgba(0,0,0,0.2); padding:0.4rem; border-radius:6px; margin-bottom:0.8rem; letter-spacing: 2px;">
                492 817
            </div>
            <div style="display:flex; gap:0.5rem;">
                <button id="sim-btn-accept" style="flex:1; background:var(--accent); color:white; border:none; padding:0.4rem; border-radius:6px; font-size:0.8rem; font-weight:600; cursor:pointer;">同意配对</button>
                <button style="background:rgba(255,255,255,0.05); color:var(--text-secondary); border:1px solid var(--border-color); padding:0.4rem; border-radius:6px; font-size:0.8rem; cursor:pointer;">拒绝</button>
            </div>
        `;
        chatBody.appendChild(card);
        scrollToBottom();

        // 模拟一秒后自动点击“同意配对”
        await delay(1200);
        const acceptBtn = card.querySelector('#sim-btn-accept');
        if (acceptBtn) {
            acceptBtn.style.background = '#10b981';
            acceptBtn.textContent = '已同意';
        }
        await delay(400);
    }

    // 运行完整的模拟器演示流程
    async function runSimulatorDemo() {
        while (true) {
            // 重置状态
            chatBody.innerHTML = '';
            setInputPlaceholder('正在搜索局域网设备...');
            peerName.textContent = '未连接设备';
            await delay(1500);

            // 发现设备
            setInputPlaceholder('发现局域网设备: Galaxy S24...');
            peerName.textContent = 'Galaxy S24 (发现中)';
            await delay(1200);

            // 弹出配对框
            setInputPlaceholder('正在等待配对验证...');
            await appendPairingCard();

            // 完成配对
            appendSeparator('已建立可信安全加密通道');
            peerName.textContent = 'Galaxy S24 (已加密连接)';
            setInputPlaceholder('在聊天框内输入要发送的内容...');
            await delay(1000);

            // 发送文字
            await typeInputText('哈罗！给你发个今天的设计图和 Android 安装包 🚀');
            await delay(300);
            appendMessage('哈罗！给你发个今天的设计图和 Android 安装包 🚀', true);
            setInputPlaceholder('在聊天框内输入要发送的内容...');
            await delay(1200);

            // 发送文件 1 (图片)
            await appendFileTransfer('design_draft_v2.webp', '2.4 MB', 1500);
            await delay(1000);

            // 发送文件 2 (APK)
            await appendFileTransfer('LocalChat-v1.3.2.apk', '15.8 MB', 2800);
            await delay(1200);

            // 接收回复
            appendMessage('收到！传输速度吃满宽带了，接收直接按类型归档了，太方便了 👍', false);
            await delay(6000); // 停留展示 6 秒后重启循环
        }
    }

    // 启动模拟器
    runSimulatorDemo();

    // ----------------------------------------------------
    // 2. 页面元素滚动展现动效 (Scroll Reveal)
    // ----------------------------------------------------
    const cards = document.querySelectorAll('.animate-card');

    const observerOptions = {
        root: null,
        threshold: 0.1,
        rootMargin: '0px 0px -50px 0px'
    };

    const cardObserver = new IntersectionObserver((entries, observer) => {
        entries.forEach(entry => {
            if (entry.isIntersecting) {
                entry.target.classList.add('fade-in-visible');
                observer.unobserve(entry.target);
            }
        });
    }, observerOptions);

    cards.forEach(card => {
        cardObserver.observe(card);
    });
});
