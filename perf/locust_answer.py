"""
eval_new 答题并发压测
模拟大量用户同时登录、加载答题页、保存草稿、提交评价的完整答题流程
压测目标: eval-answer-boot (8081) + eval-boot (8080)
"""
import json
import random
import string
from locust import HttpUser, task, between, tag, events


def random_code(prefix="PERF"):
    return f"{prefix}_{''.join(random.choices(string.ascii_uppercase + string.digits, k=8))}"


def random_name(prefix="性能测试"):
    return f"{prefix}_{random.randint(10000, 99999)}"


# 全局缓存：所有用户共享已创建的任务和账号
_shared_task_ids = []
_shared_anonymous_accounts = []  # [(account_code, password, task_id), ...]


class AnswerFlowUser(HttpUser):
    """答题流程用户 - 模拟真实答题行为"""

    wait_time = between(1, 5)  # 答题思考时间
    host = "http://localhost:8081"

    # 当前用户的答题状态
    task_id = None
    evaluatee_id = None
    account_code = None
    account_password = None
    is_logged_in = False

    def on_start(self):
        """用户开始 - 选择一个任务进行答题"""
        self._pick_task_and_login()

    def _pick_task_and_login(self):
        """选择任务并登录"""
        if _shared_anonymous_accounts:
            account = random.choice(_shared_anonymous_accounts)
            self.account_code = account[0]
            self.account_password = account[1]
            self.task_id = account[2]
            self._login_anonymous()
        # 如果没有可用账号，先创建任务数据（通过管理端 API）

    def _login_anonymous(self):
        """匿名账号登录"""
        with self.client.post(
            "/api/auth/anonymous-login",
            json={
                "accountCode": self.account_code,
                "password": self.account_password,
            },
            name="/api/auth/anonymous-login [POST]",
            catch_response=True,
        ) as resp:
            if resp.status_code == 200:
                data = resp.json()
                if data.get("code") == 0:
                    self.is_logged_in = True
                    resp.success()
                else:
                    resp.failure(f"login failed: {data.get('message', 'unknown')}")
            else:
                resp.failure(f"status={resp.status_code}")

    @tag("answer_load")
    @task(5)
    def load_answer_page(self):
        """加载答题页面 - 高频读取操作"""
        if not self.is_logged_in:
            return
        self.client.get(
            f"/api/answers/{self.task_id}/page",
            name="/api/answers/{taskId}/page [GET]",
        )

    @tag("answer_save")
    @task(3)
    def save_draft(self):
        """保存草稿 - 答题过程中频繁保存"""
        if not self.is_logged_in:
            return
        payload = {
            "taskId": self.task_id,
            "evaluateeId": self.evaluatee_id or random.randint(1, 1000),
            "answers": [
                {
                    "taskQuestionCode": f"Q1_{random.randint(1000, 9999)}",
                    "optionValues": ["good"],
                    "scoreValue": 4,
                }
            ],
        }
        self.client.post(
            "/api/answers/draft",
            json=payload,
            name="/api/answers/draft [POST]",
        )

    @tag("answer_submit")
    @task(1)
    def submit_answer(self):
        """提交评价 - 低频但关键操作"""
        if not self.is_logged_in:
            return
        payload = {
            "taskId": self.task_id,
            "evaluateeId": self.evaluatee_id or random.randint(1, 1000),
            "answers": [
                {
                    "taskQuestionCode": f"Q1_{random.randint(1000, 9999)}",
                    "optionValues": ["excellent"],
                    "scoreValue": 5,
                },
                {
                    "taskQuestionCode": f"Q2_{random.randint(1000, 9999)}",
                    "scoreValue": random.randint(6, 10),
                },
                {
                    "taskQuestionCode": f"Q3_{random.randint(1000, 9999)}",
                    "textValue": "该同事工作认真负责，团队协作能力强",
                },
            ],
        }
        self.client.post(
            "/api/answers/submit",
            json=payload,
            name="/api/answers/submit [POST]",
        )

    @tag("answer_abandon")
    @task(1)
    def abandon_answer(self):
        """弃权 - 少数情况"""
        if not self.is_logged_in:
            return
        payload = {
            "taskId": self.task_id,
            "evaluateeId": self.evaluatee_id or random.randint(1, 1000),
            "abandonReason": "对该被评人不够了解",
        }
        self.client.post(
            "/api/answers/abandon",
            json=payload,
            name="/api/answers/abandon [POST]",
        )


class DataPrepUser(HttpUser):
    """
    数据准备用户 - 在答题压测前先创建好任务和匿名账号
    使用管理端 API (8080) 创建数据
    """

    wait_time = between(0.1, 0.5)
    host = "http://localhost:8080"

    category_id = None
    scenario_id = None
    template_id = None

    def on_start(self):
        """初始化基础数据"""
        self._ensure_base_data()

    def _ensure_base_data(self):
        """确保场景分类和场景存在"""
        if self.category_id and self.scenario_id:
            return

        # 创建场景分类
        with self.client.post(
            "/api/scenario-categories",
            json={
                "name": "性能测试分类",
                "code": f"PERF_CAT_{random.randint(1000, 9999)}",
                "description": "性能测试专用",
                "sortOrder": 0,
            },
            name="[PREP] /api/scenario-categories [POST]",
            catch_response=True,
        ) as resp:
            if resp.status_code == 200:
                data = resp.json()
                if data.get("code") == 0 and data.get("data"):
                    self.category_id = data["data"]
                resp.success()

        if not self.category_id:
            return

        # 创建场景
        with self.client.post(
            "/api/scenarios",
            json={
                "name": "性能测试场景",
                "code": f"PERF_SCN_{random.randint(1000, 9999)}",
                "categoryId": self.category_id,
                "description": "性能测试专用",
            },
            name="[PREP] /api/scenarios [POST]",
            catch_response=True,
        ) as resp:
            if resp.status_code == 200:
                data = resp.json()
                if data.get("code") == 0 and data.get("data"):
                    self.scenario_id = data["data"]
                resp.success()

        if not self.scenario_id:
            return

        # 创建模板
        with self.client.post(
            "/api/templates",
            json={
                "name": "性能测试模板",
                "scenarioId": self.scenario_id,
                "scoringEnabled": True,
                "questionGroups": [
                    {"code": "G_PERF", "name": "综合评估", "sortOrder": 1}
                ],
                "questions": [
                    {
                        "code": "Q_PERF_1",
                        "type": "SINGLE_CHOICE",
                        "title": "整体表现",
                        "required": True,
                        "sortOrder": 1,
                        "options": [
                            {"label": "优秀", "value": "excellent", "scoreValue": 5, "sortOrder": 1},
                            {"label": "良好", "value": "good", "scoreValue": 4, "sortOrder": 2},
                            {"label": "一般", "value": "average", "scoreValue": 3, "sortOrder": 3},
                            {"label": "较差", "value": "poor", "scoreValue": 2, "sortOrder": 4},
                        ],
                    },
                    {
                        "code": "Q_PERF_2",
                        "type": "SCORE",
                        "title": "能力评分",
                        "required": True,
                        "sortOrder": 2,
                        "scoreConfig": {"maxScore": 10, "minScore": 0, "step": 1, "defaultScore": 5},
                    },
                    {
                        "code": "Q_PERF_3",
                        "type": "TEXT",
                        "title": "补充说明",
                        "required": False,
                        "sortOrder": 3,
                        "textConfig": {"maxLength": 500, "placeholder": "请输入..."},
                    },
                ],
                "scoringRule": {
                    "aggregationMethod": "WEIGHTED_AVG",
                    "totalScore": 100,
                    "decimalPlaces": 2,
                },
            },
            name="[PREP] /api/templates [POST]",
            catch_response=True,
        ) as resp:
            if resp.status_code == 200:
                data = resp.json()
                if data.get("code") == 0 and data.get("data"):
                    self.template_id = data["data"]
                resp.success()

        # 发布模板
        if self.template_id:
            self.client.post(
                f"/api/templates/{self.template_id}/publish",
                name="[PREP] /api/templates/{id}/publish [POST]",
            )

    @task(1)
    def create_task_with_evaluators(self):
        """创建任务并生成匿名账号 - 为答题压测准备数据"""
        if not self.template_id or not self.scenario_id:
            self._ensure_base_data()
            return

        # 创建人员作为被评人和评价者
        evaluatee_ids = []
        evaluator_ids = []
        for _ in range(3):
            with self.client.post(
                "/api/persons",
                json={
                    "employeeNo": random_code("EMP"),
                    "name": random_name("被评人"),
                    "department": "测试部",
                    "status": "ACTIVE",
                },
                name="[PREP] /api/persons [POST]",
                catch_response=True,
            ) as resp:
                if resp.status_code == 200:
                    data = resp.json()
                    if data.get("code") == 0 and data.get("data"):
                        evaluatee_ids.append(data["data"])
                    resp.success()

        for _ in range(5):
            with self.client.post(
                "/api/persons",
                json={
                    "employeeNo": random_code("EVR"),
                    "name": random_name("评价人"),
                    "department": "测试部",
                    "status": "ACTIVE",
                },
                name="[PREP] /api/persons [POST]",
                catch_response=True,
            ) as resp:
                if resp.status_code == 200:
                    data = resp.json()
                    if data.get("code") == 0 and data.get("data"):
                        evaluator_ids.append(data["data"])
                    resp.success()

        if not evaluatee_ids or not evaluator_ids:
            return

        # 构建评价者列表
        evaluators = []
        evr_idx = 0
        for i, eid in enumerate(evaluatee_ids):
            for _ in range(min(2, len(evaluator_ids))):
                evaluators.append({
                    "evaluateeIndex": i,
                    "evaluatorId": evaluator_ids[evr_idx % len(evaluator_ids)],
                    "evaluatorRole": random.choice(["PEER", "LEADER", "SELF"]),
                    "weight": 1.0,
                })
                evr_idx += 1

        # 创建任务（匿名模式）
        with self.client.post(
            "/api/tasks",
            json={
                "name": random_name("压测任务"),
                "templateId": self.template_id,
                "scenarioId": self.scenario_id,
                "startTime": "2026-01-01T00:00:00",
                "endTime": "2026-12-31T23:59:59",
                "evaluatorMode": "ASSIGNED_ANONYMOUS",
                "evaluatees": [
                    {"objectType": "PERSON", "objectId": eid, "objectName": f"被评人_{i}"}
                    for i, eid in enumerate(evaluatee_ids)
                ],
                "evaluators": evaluators,
            },
            name="[PREP] /api/tasks [POST]",
            catch_response=True,
        ) as resp:
            if resp.status_code == 200:
                data = resp.json()
                if data.get("code") == 0 and data.get("data"):
                    task_id = data["data"]
                    _shared_task_ids.append(task_id)
                resp.success()
            else:
                resp.failure(f"status={resp.status_code}")
