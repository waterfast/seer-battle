-- SPDX-License-Identifier: LGPL-2.1-or-later
return sr.createEffectSkeleton {
    id = 10051,
    event = sr.BeforeActionOrder,
    validate_on_usevalue = function(parameters)
        assert(math.type(parameters.amount) == "integer", "priority amount must be an integer")
    end,
    can_trigger = function(self, event, target, owner, data)
        return owner.alive and data.from == owner and data.type == "skill" and data.skill ~= nil
            and (data.skill.type == "physical" or data.skill.type == "special")
    end,
    on_use = function(self, event, target, owner, data, parameters)
        data.priority = data.priority + parameters.amount
    end,
}
