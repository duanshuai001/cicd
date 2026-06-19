"""
eval_new 基准摸底压测
覆盖所有核心 API，逐步加压，摸清各接口容量上限
"""
import json
import random
import string
from locust import HttpUser, task, between, tag


def random_code(prefix="PERF"):
    return f"{prefix}_{''.join(random.choices(string.ascii_uppercase + string.digits, k=8))}"


def random_name(prefix="性能测试"):
    return f"{prefix}_{random.randint(10000, 99999)}"


class EvalBaselineUser(HttpUser):
    """基准摸底用户 - 按真实业务权重分配请求"""

    wait_time = between(0.5, 2)
    host = "http://localhost:8080"

    # 已创建的资源 ID 缓存（每个用户独立）
    created_category_ids = None
    created_scenario_ids = None
    created_template_ids = None
    created_task_ids = None
    created_person_ids = None
    created_org_ids = None

    def on_start(self):
        self.created_category_ids = []
        self.created_scenario_ids = []
        self.created_template_ids = []
        self.created_task_ids = []
        self.created_person_ids = []
        self.created_org_ids = []

    # ---- 基础数据域 ----

    @tag("person")
    @task(3)
    def create_person(self):
        """创建人员 - 高频操作"""
        payload = {
            "employeeNo": random_code("EMP"),
            "name": random_name("人员"),
            "department": f"测试部门_{random.randint(1, 10)}",
            "position": "工程师",
            "jobLevel": "P7",
            "status": "ACTIVE",
        }
        with self.client.post(
            "/api/persons",
            json=payload,
            name="/api/persons [POST]",
            catch_response=True,
        ) as resp:
            if resp.status_code == 200:
                data = resp.json()
                if data.get("code") == 0 and data.get("data"):
                    self.created_person_ids.append(data["data"])
                resp.success()
            else:
                resp.failure(f"status={resp.status_code}")

    @tag("person")
    @task(2)
    def list_persons(self):
        """查询人员列表"""
        self.client.get("/api/persons", name="/api/persons [GET]")

    @tag("org")
    @task(2)
    def create_organization(self):
        """创建组织"""
        payload = {
            "orgCode": random_code("ORG"),
            "name": random_name("组织"),
            "industry": "互联网",
            "qualification": "A级",
            "status": "ACTIVE",
        }
        with self.client.post(
            "/api/organizations",
            json=payload,
            name="/api/organizations [POST]",
            catch_response=True,
        ) as resp:
            if resp.status_code == 200:
                data = resp.json()
                if data.get("code") == 0 and data.get("data"):
                    self.created_org_ids.append(data["data"])
                resp.success()
            else:
                resp.failure(f"status={resp.status_code}")

    @tag("org")
    @task(1)
    def list_organizations(self):
        """查询组织列表"""
        self.client.get("/api/organizations", name="/api/organizations [GET]")

    # ---- 场景管理域 ----

    @tag("scenario")
    @task(3)
    def create_scenario_category(self):
        """创建场景分类"""
        payload = {
            "name": random_name("分类"),
            "code": random_code("CAT"),
            "description": "性能测试自动创建",
            "sortOrder": random.randint(0, 100),
        }
        with self.client.post(
            "/api/scenario-categories",
            json=payload,
            name="/api/scenario-categories [POST]",
            catch_response=True,
        ) as resp:
            if resp.status_code == 200:
                data = resp.json()
                if data.get("code") == 0 and data.get("data"):
                    self.created_category_ids.append(data["data"])
                resp.success()
            else:
                resp.failure(f"status={resp.status_code}")

    @tag("scenario")
    @task(2)
    def list_scenario_categories(self):
        """查询场景分类列表"""
        self.client.get("/api/scenario-categories", name="/api/scenario-categories [GET]")

    @tag("scenario")
    @task(3)
    def create_scenario(self):
        """创建场景"""
        category_id = self._pick_id(self.created_category_ids, 1)
        payload = {
            "name": random_name("场景"),
            "code": random_code("SCN"),
            "categoryId": category_id,
            "description": "性能测试自动创建",
        }
        with self.client.post(
            "/api/scenarios",
            json=payload,
            name="/api/scenarios [POST]",
            catch_response=True,
        ) as resp:
            if resp.status_code == 200:
                data = resp.json()
                if data.get("code") == 0 and data.get("data"):
                    self.created_scenario_ids.append(data["data"])
                resp.success()
            else:
                resp.failure(f"status={resp.status_code}")

    @tag("scenario")
    @task(2)
    def list_scenarios(self):
        """查询场景列表"""
        self.client.get("/api/scenarios", name="/api/scenarios [GET]")

    # ---- 模板管理域 ----

    @tag("template")
    @task(2)
    def create_template(self):
        """创建模板 - 含题目和计分规则"""
        scenario_id = self._pick_id(self.created_scenario_ids, 1)
        payload = {
            "name": random_name("模板"),
            "scenarioId": scenario_id,
            "description": "性能测试自动创建",
            "scoringEnabled": True,
            "questionGroups": [
                {
                    "code": f"G1_{random.randint(1000, 9999)}",
                    "name": "工作能力",
                    "description": "工作能力评估",
                    "sortOrder": 1,
                }
            ],
            "questions": [
                {
                    "code": f"Q1_{random.randint(1000, 9999)}",
                    "groupCode": None,
                    "type": "SINGLE_CHOICE",
                    "title": "整体工作表现如何？",
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
                    "code": f"Q2_{random.randint(1000, 9999)}",
                    "groupCode": None,
                    "type": "SCORE",
                    "title": "团队协作能力评分",
                    "required": True,
                    "sortOrder": 2,
                    "scoreConfig": {
                        "maxScore": 10,
                        "minScore": 0,
                        "step": 1,
                        "defaultScore": 5,
                    },
                },
                {
                    "code": f"Q3_{random.randint(1000, 9999)}",
                    "groupCode": None,
                    "type": "TEXT",
                    "title": "请简述该同事的突出优点",
                    "required": False,
                    "sortOrder": 3,
                    "textConfig": {
                        "maxLength": 500,
                        "placeholder": "请输入...",
                    },
                },
            ],
            "scoringRule": {
                "aggregationMethod": "WEIGHTED_AVG",
                "totalScore": 100,
                "decimalPlaces": 2,
            },
        }
        with self.client.post(
            "/api/templates",
            json=payload,
            name="/api/templates [POST]",
            catch_response=True,
        ) as resp:
            if resp.status_code == 200:
                data = resp.json()
                if data.get("code") == 0 and data.get("data"):
                    self.created_template_ids.append(data["data"])
                resp.success()
            else:
                resp.failure(f"status={resp.status_code}")

    @tag("template")
    @task(3)
    def get_template(self):
        """查询模板详情"""
        template_id = self._pick_id(self.created_template_ids)
        if template_id:
            self.client.get(
                f"/api/templates/{template_id}",
                name="/api/templates/{id} [GET]",
            )

    @tag("template")
    @task(2)
    def list_templates(self):
        """查询模板列表"""
        self.client.get("/api/templates", name="/api/templates [GET]")

    # ---- 任务管理域 ----

    @tag("task")
    @task(2)
    def create_task(self):
        """创建任务 - 含被测评人和评价者"""
        scenario_id = self._pick_id(self.created_scenario_ids, 1)
        template_id = self._pick_id(self.created_template_ids, 1)
        payload = {
            "name": random_name("任务"),
            "templateId": template_id,
            "scenarioId": scenario_id,
            "startTime": "2026-01-01T00:00:00",
            "endTime": "2026-12-31T23:59:59",
            "evaluatorMode": "ASSIGNED_REALNAME",
            "evaluatees": [
                {
                    "objectType": "PERSON",
                    "objectId": self._pick_id(self.created_person_ids, 1),
                    "objectName": random_name("被评人"),
                }
            ],
            "evaluators": [
                {
                    "evaluateeIndex": 0,
                    "evaluatorId": self._pick_id(self.created_person_ids, 2),
                    "evaluatorRole": "PEER",
                    "weight": 1.0,
                }
            ],
        }
        with self.client.post(
            "/api/tasks",
            json=payload,
            name="/api/tasks [POST]",
            catch_response=True,
        ) as resp:
            if resp.status_code == 200:
                data = resp.json()
                if data.get("code") == 0 and data.get("data"):
                    self.created_task_ids.append(data["data"])
                resp.success()
            else:
                resp.failure(f"status={resp.status_code}")

    @tag("task")
    @task(3)
    def get_task(self):
        """查询任务信息"""
        task_id = self._pick_id(self.created_task_ids)
        if task_id:
            self.client.get(
                f"/api/tasks/{task_id}",
                name="/api/tasks/{id} [GET]",
            )

    @tag("task")
    @task(2)
    def get_task_detail(self):
        """查询任务详情 - 复杂聚合查询"""
        task_id = self._pick_id(self.created_task_ids)
        if task_id:
            self.client.get(
                f"/api/tasks/{task_id}/detail",
                name="/api/tasks/{id}/detail [GET]",
            )

    @tag("task")
    @task(2)
    def list_tasks(self):
        """查询任务列表"""
        self.client.get("/api/tasks", name="/api/tasks [GET]")

    # ---- 跟踪域 ----

    @tag("tracking")
    @task(2)
    def get_tracking(self):
        """查询任务跟踪"""
        task_id = self._pick_id(self.created_task_ids)
        if task_id:
            self.client.get(
                f"/api/tracking/{task_id}",
                name="/api/tracking/{taskId} [GET]",
            )

    @tag("tracking")
    @task(1)
    def list_tracking(self):
        """查询跟踪列表"""
        self.client.get("/api/tracking", name="/api/tracking [GET]")

    # ---- 结果域 ----

    @tag("result")
    @task(2)
    def get_result_overview(self):
        """查询结果概览"""
        task_id = self._pick_id(self.created_task_ids)
        if task_id:
            self.client.get(
                f"/api/results/{task_id}/overview",
                name="/api/results/{taskId}/overview [GET]",
            )

    @tag("result")
    @task(1)
    def get_result_detail(self):
        """查询结果详情"""
        task_id = self._pick_id(self.created_task_ids)
        if task_id:
            self.client.get(
                f"/api/results/{task_id}/detail",
                name="/api/results/{taskId}/detail [GET]",
            )

    # ---- 工具方法 ----

    def _pick_id(self, id_list, fallback=None):
        """从缓存中随机选一个 ID，没有则用 fallback"""
        if id_list:
            return random.choice(id_list)
        return fallback
