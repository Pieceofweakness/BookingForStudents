document.addEventListener('DOMContentLoaded', () => {
        const form = document.getElementById('loginForm');
        const emailInput = document.getElementById('email');
        const passwordInput = document.getElementById('password');
        const emailError = document.getElementById('emailError');
        const passwordError = document.getElementById('passwordError');
        const submitBtn = document.getElementById('submitBtn');
        const toast = document.getElementById('toast');
        const togglePass = document.getElementById('togglePass');

        // Show/hide password
        togglePass.addEventListener('click', () => {
            const isPass = passwordInput.type === 'password';
            passwordInput.type = isPass ? 'text' : 'password';
            togglePass.textContent = isPass ? '🙈' : '👁';
            togglePass.setAttribute('aria-label', isPass ? 'Hide password' : 'Show password');
        });

        function showToast(message, type = 'error') {
            toast.textContent = message;
            toast.className = `toast ${type} show`;
            clearTimeout(showToast._t);
            showToast._t = setTimeout(() => {
                toast.classList.remove('show');
            }, 3500);
        }

        function validateEmail(value) {
            // Simple RFC-ish pattern
            return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value.trim());
        }

        function setFieldError(input, errorEl, hasError) {
            input.classList.toggle('invalid', hasError);
            errorEl.classList.toggle('visible', hasError);
        }

        // Live validation
        emailInput.addEventListener('input', () => {
            const ok = validateEmail(emailInput.value);
            setFieldError(emailInput, emailError, !ok && emailInput.value.length > 0);
        });
        passwordInput.addEventListener('input', () => {
            const ok = passwordInput.value.length >= 6;
            setFieldError(passwordInput, passwordError, !ok && passwordInput.value.length > 0);
        });

        form.addEventListener('submit', async (e) => {
            e.preventDefault();

            const email = emailInput.value.trim();
            const password = passwordInput.value;
            

            let valid = true;

            if (!validateEmail(email)) {
                setFieldError(emailInput, emailError, true);
                valid = false;
            } else {
                setFieldError(emailInput, emailError, false);
            }

            if (password.length < 6) {
                setFieldError(passwordInput, passwordError, true);
                valid = false;
            } else {
                setFieldError(passwordInput, passwordError, false);
            }

            if (!valid) {
                showToast('Пожалуйста проверьте отмеченные поля', 'error');
                return;
            }

            // Simulate API call
            submitBtn.disabled = true;
            submitBtn.textContent = 'Signing in...';

            try {
                await fakeAuthRequest({ email, password });
                showToast(`Добро пожаловать!`, 'success');
                // window.location.href = role === 'teacher' ? '/teacher/dashboard' : '/student/schedule';
            } catch (err) {
                showToast(err.message || 'Неверный логин или пароль', 'error');
            } finally {
                submitBtn.disabled = false;
                submitBtn.textContent = 'Sign In';
            }
        });

        // Replace with real fetch to your backend
        function fakeAuthRequest(data) {
            return new Promise((resolve, reject) => {
                setTimeout(() => {
                    if (data.email === 'fail@test.com') {
                        reject(new Error('Invalid email or password.'));
                    } else {
                        resolve({ token: 'demo-token', user: data });
                    }
                }, 900);
            });
        }
    });